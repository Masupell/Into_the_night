"""Water surface level from the converted ETOPO heights, only the ocean for now.

The ocean is the biggest connected area below sea level, everything else below 0 (Dead Sea, Caspian, ...) is dry.
Dry pixels get a level below the lowest ground around them instead of a no-water value, the game interpolates
the coarse water grid and that would give wrong levels near the edges.

Output:
  <out>.bin   int16 little endian meters, same layout as the input
  <out>.json  width, height, format and source

Usage (from the project root):
  tools/.venv/bin/python tools/convert_water.py data/etopo_30s data/water_30s
"""

import argparse
import json
from pathlib import Path

import numpy as np
import scipy.ndimage as nd

DRY_RADIUS = 3  # pixels, a bit more than one water pixel at the finest tile level
DRY_MARGIN = 10  # meters under the lowest ground around


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path, help="converted elevation file without extension")
    parser.add_argument("output", type=Path, help="output path without extension")
    args = parser.parse_args()

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

    dry = below & ~ocean
    print(f"{count} areas below sea level, ocean {ocean.mean() * 100:.1f} %, dry {dry.sum()} pixels")
    del below

    size = 2 * DRY_RADIUS + 1
    near_dry = nd.binary_dilation(dry, structure=np.ones((size, size), dtype=bool)) & ~ocean
    del dry, ocean
    lowest = nd.minimum_filter(heights, size=size, mode=("nearest", "wrap"))
    water = np.zeros(heights.shape, dtype="<i2")
    water[near_dry] = np.minimum(lowest[near_dry].astype(np.int32) - DRY_MARGIN, 0)

    water.tofile(args.output.with_suffix(".bin"))
    out_info = {
        "width": info["width"],
        "height": info["height"],
        "format": "int16_le_water_meters",
        "layout": info["layout"],
        "source": info["source"],
    }
    args.output.with_suffix(".json").write_text(json.dumps(out_info, indent=2) + "\n")
    print(f"wrote {args.output.with_suffix('.bin')}: {water.nbytes / 1e9:.2f} GB")


if __name__ == "__main__":
    main()
