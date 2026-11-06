"""Water surface level from the converted ETOPO heights: the ocean and the lakes from HydroLAKES.

The ocean is the biggest connected area below sea level, everything else below 0 without a lake is dry.
Dry pixels get a level below the lowest ground around them instead of a no-water value, the game interpolates
the coarse water grid and that would give wrong levels near the edges. For the same reason the land around a lake
gets the lake level too, as long as it is higher than the lake.

Lake beds are carved into the heights, unless ETOPO already has the real bed (Caspian, Baikal, Great Lakes, ...).
Without a bed ETOPO has the lake flat at its own surface height, which doesn't always match HydroLAKES
(Titicaca 3808 vs 3815 m), then the ETOPO one is used so the lake fits the land around it.

HydroLAKES v1.0 (Messager et al. 2016, https://www.hydrosheds.org/products/hydrolakes), license CC BY 4.0

Output:
  <out>.bin            int16 little endian meters, same layout as the input
  <out>.json           width, height, format and source
  <heights_out>.bin    heights with the carved lake beds, same format as the input

Usage (from the project root):
  tools/.venv/bin/python tools/convert_water.py data/etopo_30s data/water_30s \\
      --lakes data/source/HydroLAKES_polys_v10_shp.zip --heights-out data/etopo_lakes_30s
"""

import argparse
import json
import time
from pathlib import Path

import numpy as np
import rasterio.features
import rasterio.transform
import scipy.ndimage as nd
import shapely
from pyogrio.raw import read

DRY_RADIUS = 3  # pixels, a bit more than one water pixel at the finest tile level
DRY_MARGIN = 10  # meters under the lowest ground around
MIN_LAKE_AREA = 1.0  # km2, smaller ones don't hit a pixel anyway
LAKE_RING = 3  # pixels around a lake that get its level
SHORE_DEPTH = 2  # meters at the shore
DEPTH_PER_PIXEL = 5  # meters deeper per pixel away from the shore
HAS_BED = 10  # lakes with ground this far under their surface already have their real bed in ETOPO
ABOVE_LAKE = 20  # meters, higher pixels in a lake outline stay land (islands, outline not matching ETOPO)
FADE_PIXELS = 12  # around a lake the level sinks slowly instead of jumping, the game fades the detail with it
FADE_SLOPE = 40  # meters per pixel, FADE_PIXELS * FADE_SLOPE has to cover the game's detail fade (442 m)


def read_lakes(path):
    shp = f"/vsizip/{path}/HydroLAKES_polys_v10_shp/HydroLAKES_polys_v10.shp"
    _, _, wkb, (area, depth, elevation) = read(shp, columns=["Lake_area", "Depth_avg", "Elevation"])
    keep = area >= MIN_LAKE_AREA
    return shapely.from_wkb(wkb[keep]), depth[keep], elevation[keep]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path, help="converted elevation file without extension")
    parser.add_argument("output", type=Path, help="output path without extension")
    parser.add_argument("--lakes", type=Path, help="HydroLAKES_polys_v10_shp.zip")
    parser.add_argument("--heights-out", type=Path, help="output for the heights with carved lake beds")
    args = parser.parse_args()
    start = time.time()

    info = json.loads(args.input.with_suffix(".json").read_text())
    assert info["format"] == "int16_le_meters"
    heights = np.fromfile(args.input.with_suffix(".bin"), dtype="<i2").reshape(info["height"], info["width"])

    below = heights < 0
    labels, count = nd.label(below, structure=np.ones((3, 3), dtype=bool))
    # 180W and 180E are neighbours
    left, right = labels[:, 0], labels[:, -1]
    both = (left > 0) & (right > 0)
    sizes = np.bincount(labels.ravel())
    sizes[0] = 0
    ocean_labels = {int(np.argmax(sizes))}
    for a, b in zip(left[both], right[both]):
        if a in ocean_labels or b in ocean_labels:
            ocean_labels.update((int(a), int(b)))
    ocean = np.isin(labels, list(ocean_labels))
    del labels
    print(f"{count} areas below sea level, ocean {ocean.mean() * 100:.1f} % ({time.time() - start:.0f} s)")

    lake_ids = np.zeros(heights.shape, dtype=np.int32)
    if args.lakes:
        geometries, lake_depths, lake_levels = read_lakes(args.lakes)
        print(f"{len(geometries)} lakes from {MIN_LAKE_AREA} km2 ({time.time() - start:.0f} s)")
        transform = rasterio.transform.from_origin(-180.0, 90.0, 360.0 / info["width"], 180.0 / info["height"])
        rasterio.features.rasterize(zip(geometries, range(1, len(geometries) + 1)), out=lake_ids, transform=transform)
        del geometries
        lake_ids[ocean] = 0
    lake = lake_ids > 0

    dry = below & ~ocean & ~lake
    print(f"dry {dry.sum()} pixels, lakes {lake.sum()} pixels ({time.time() - start:.0f} s)")
    del below

    size = 2 * DRY_RADIUS + 1
    near_dry = nd.binary_dilation(dry, structure=np.ones((size, size), dtype=bool)) & ~ocean
    del dry
    lowest = nd.minimum_filter(heights, size=size, mode=("nearest", "wrap"))
    water = np.zeros(heights.shape, dtype="<i2")
    water[near_dry] = np.minimum(lowest[near_dry].astype(np.int32) - DRY_MARGIN, 0)
    del near_dry, lowest

    lowest_land = nd.minimum_filter(np.where(ocean | lake, np.int16(32767), heights), size=size, mode=("nearest", "wrap"))
    carved = heights.copy()
    ring_structure = np.ones((2 * LAKE_RING + 1, 2 * LAKE_RING + 1), dtype=bool)
    for i, box in enumerate(nd.find_objects(lake_ids)):
        if box is None:
            continue
        level = int(lake_levels[i])
        reach = LAKE_RING + FADE_PIXELS
        ys = slice(max(box[0].start - reach, 0), min(box[0].stop + reach, heights.shape[0]))
        xs = slice(max(box[1].start - reach, 0), min(box[1].stop + reach, heights.shape[1]))
        mask = lake_ids[ys, xs] == i + 1
        ground = heights[ys, xs]

        has_bed = ground[mask].min() <= level - HAS_BED
        if not has_bed:
            level = int(np.median(ground[mask]))
        land = mask & (ground > level + ABOVE_LAKE)
        if land.any():
            mask &= ~land
            lake_ids[ys, xs][land] = 0
            lake[ys, xs][land] = False
            if not mask.any():
                continue

        bed = np.full(mask.shape, level - SHORE_DEPTH, dtype=np.int32)
        if not has_bed:
            shore_distance = nd.distance_transform_edt(np.pad(mask, 1))[1:-1, 1:-1]
            max_depth = max(lake_depths[i] * 2.0, SHORE_DEPTH)
            bed -= np.minimum(shore_distance * DEPTH_PER_PIXEL, max_depth - SHORE_DEPTH).astype(np.int32)
        carved[ys, xs][mask] = np.minimum(ground[mask], bed[mask])
        water[ys, xs][mask] = level

        ring = nd.binary_dilation(mask, structure=ring_structure) & ~lake[ys, xs] & ~ocean[ys, xs] & (ground >= level)
        water[ys, xs][ring] = np.maximum(water[ys, xs][ring], level)

        # always under the ground, also below dams
        distance = nd.distance_transform_edt(~mask)
        fade = (distance <= reach) & ~ring & ~lake[ys, xs] & ~ocean[ys, xs]
        sinking = np.minimum(level, lowest_land[ys, xs][fade].astype(np.int32) - DRY_MARGIN) - FADE_SLOPE * np.maximum(distance[fade] - LAKE_RING, 0.0)
        water[ys, xs][fade] = np.maximum(water[ys, xs][fade], np.clip(sinking, -32768, 32767).astype(np.int16))
    del lowest_land
    print(f"lakes done ({time.time() - start:.0f} s)")

    water.tofile(args.output.with_suffix(".bin"))
    out_info = {
        "width": info["width"],
        "height": info["height"],
        "format": "int16_le_water_meters",
        "layout": info["layout"],
        "source": info["source"] + (", HydroLAKES v1.0 (CC BY 4.0)" if args.lakes else ""),
    }
    args.output.with_suffix(".json").write_text(json.dumps(out_info, indent=2) + "\n")
    print(f"wrote {args.output.with_suffix('.bin')}")

    if args.heights_out:
        carved.tofile(args.heights_out.with_suffix(".bin"))
        heights_info = dict(info, source=out_info["source"] + ", lake beds carved")
        args.heights_out.with_suffix(".json").write_text(json.dumps(heights_info, indent=2) + "\n")
        print(f"wrote {args.heights_out.with_suffix('.bin')}")


if __name__ == "__main__":
    main()
