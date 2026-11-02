"""Bakes the tile pyramid from a converted equirect file (heights, moisture or water) into one pack file.

Must match CubeSphere.FACES / face_to_sphere, TerrainTile.pixel_to_dir and EquirectSource.get_uv / sample.

Output:
  <out>.bin   all tiles, same format as the input, row major.
              Level L starts at levels[L].offset, tile (face, x, y) is at index (face * n + y) * n + x with n = 2^L
  <out>.json  tile_size, max_level, level offsets, ...

Usage (from the project root):
  tools/.venv/bin/python tools/bake_tiles.py data/etopo_30s data/earth_tiles --max-level 7
  tools/.venv/bin/python tools/bake_tiles.py data/moisture_60s data/earth_moisture --max-level 7 --tile-size 33
  tools/.venv/bin/python tools/bake_tiles.py data/water_30s data/earth_water --max-level 7 --tile-size 33
  (moisture / water: --tile-size = TerrainTile.MOISTURE_SIZE / WATER_SIZE, --max-level same as the heights)
"""

import argparse
import json
import time
from pathlib import Path

import numpy as np

# format -> numpy type
FORMATS = {
    "int16_le_meters": np.dtype("<i2"),
    "uint8_moisture": np.dtype("u1"),
    "int16_le_water_meters": np.dtype("<i2"),
}

# CubeSphere.FACES: [top_left, top_right, bottom_right, bottom_left]
FACES = np.array([
    [(-1, 1, 1), (1, 1, 1), (1, -1, 1), (-1, -1, 1)],      # 0 Front (+Z)
    [(1, 1, 1), (1, 1, -1), (1, -1, -1), (1, -1, 1)],      # 1 Right (+X)
    [(1, 1, -1), (-1, 1, -1), (-1, -1, -1), (1, -1, -1)],  # 2 Back  (-Z)
    [(-1, 1, -1), (-1, 1, 1), (-1, -1, 1), (-1, -1, -1)],  # 3 Left  (-X)
    [(-1, 1, -1), (1, 1, -1), (1, 1, 1), (-1, 1, 1)],      # 4 Top   (+Y)
    [(-1, -1, 1), (1, -1, 1), (1, -1, -1), (-1, -1, -1)],  # 5 Bottom(-Y)
], dtype=np.float64)


def face_to_sphere(face, u, v):
    c = FACES[face]
    p = c[0] + (c[1] - c[0]) * u[..., None] + (c[3] - c[0]) * v[..., None]
    x, y, z = p[..., 0], p[..., 1], p[..., 2]
    x2, y2, z2 = x * x, y * y, z * z
    return (x * np.sqrt(1 - y2 / 2 - z2 / 2 + y2 * z2 / 3),
            y * np.sqrt(1 - z2 / 2 - x2 / 2 + z2 * x2 / 3),
            z * np.sqrt(1 - x2 / 2 - y2 / 2 + x2 * y2 / 3))


def sample_equirect(data, x, y, z):
    height, width = data.shape
    length = np.sqrt(x * x + y * y + z * z)
    phi = np.arctan2(z / length, x / length)
    theta = np.arcsin(np.clip(y / length, -1.0, 1.0))
    u = (phi + np.pi) / (2 * np.pi)
    v = (theta + np.pi / 2) / np.pi

    px = u * width - 0.5
    py = np.clip(v * height - 0.5, 0.0, height - 1.0)
    x0 = np.floor(px).astype(np.int64)
    y0 = np.floor(py).astype(np.int64)
    tx = px - x0
    ty = py - y0
    x0 = np.mod(x0, width)
    x1 = (x0 + 1) % width
    y1 = np.minimum(y0 + 1, height - 1)

    top = data[y0, x0] * (1 - tx) + data[y0, x1] * tx
    bottom = data[y1, x0] * (1 - tx) + data[y1, x1] * tx
    return top * (1 - ty) + bottom * ty


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path, help="converted elevation file without extension")
    parser.add_argument("output", type=Path, help="output path without extension")
    parser.add_argument("--max-level", type=int, default=6)
    parser.add_argument("--tile-size", type=int, default=129)
    args = parser.parse_args()

    info = json.loads(args.input.with_suffix(".json").read_text())
    dtype = FORMATS[info["format"]]
    limits = np.iinfo(dtype)
    data = np.fromfile(args.input.with_suffix(".bin"), dtype=dtype).reshape(info["height"], info["width"]).astype(np.float32)

    step = args.tile_size - 1
    tile_bytes = args.tile_size * args.tile_size * dtype.itemsize
    levels = []
    offset = 0
    for level in range(args.max_level + 1):
        levels.append({"level": level, "offset": offset})
        offset += 6 * (1 << level) ** 2 * tile_bytes
    total_bytes = offset

    face_pixels = (1 << args.max_level) * step  # last pixel of a face at the finest level
    out = np.memmap(args.output.with_suffix(".bin"), dtype=dtype, mode="w+", shape=(total_bytes // dtype.itemsize,))

    start = time.time()
    for face in range(6):
        finest = np.empty((face_pixels + 1, face_pixels + 1), dtype=dtype)
        cols = np.arange(face_pixels + 1, dtype=np.float64) / face_pixels
        for row_start in range(0, face_pixels + 1, 256):
            rows = np.arange(row_start, min(row_start + 256, face_pixels + 1), dtype=np.float64) / face_pixels
            u, v = np.meshgrid(cols, rows)
            values = sample_equirect(data, *face_to_sphere(face, u, v))
            finest[row_start:row_start + len(rows)] = np.clip(np.rint(values), limits.min, limits.max)

        for level in range(args.max_level + 1):
            n = 1 << level
            grid = finest[::1 << (args.max_level - level), ::1 << (args.max_level - level)]  # every 2^k-th pixel
            for tile_y in range(n):
                for tile_x in range(n):
                    tile = grid[tile_y * step:tile_y * step + args.tile_size, tile_x * step:tile_x * step + args.tile_size]
                    index = (face * n + tile_y) * n + tile_x
                    begin = (levels[level]["offset"] + index * tile_bytes) // dtype.itemsize
                    out[begin:begin + tile.size] = tile.ravel()
        print(f"face {face} done ({time.time() - start:.0f} s)")

    out.flush()
    meta = {
        "format": info["format"],
        "tile_size": args.tile_size,
        "max_level": args.max_level,
        "tile_bytes": tile_bytes,
        "levels": levels,
        "layout": "level offset + ((face * n + tile_y) * n + tile_x) * tile_bytes, n = 2^level, pixels x + y * tile_size",
        "source": info.get("source", args.input.name),
    }
    args.output.with_suffix(".json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f"wrote {args.output.with_suffix('.bin')}: {total_bytes / 1e9:.2f} GB")


if __name__ == "__main__":
    main()
