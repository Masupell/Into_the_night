"""Bakes the terrain tile pyramid from a converted elevation file (see convert_etopo.py) into one pack file,
so the game only reads the tiles it needs instead of keeping the whole map in memory.

Must match the game code:
  - CubeSphere.FACES / face_to_sphere (cube face uv -> sphere direction)
  - TerrainTile.pixel_to_dir (tile pixel -> face uv, tiles share their border pixels)
  - EquirectSource.get_uv / sample (direction -> equirect uv, bilinear on pixel centers, wraps horizontally)

Only the finest level is sampled from the source. Every coarser level takes every second pixel of the level below,
which is exactly what the game did before (coarse pixels are also fine pixels), so chunks of different levels still meet.

Output:
  <out>.bin   all tiles, int16 little endian meters, row major (x + y * tile_size).
              Level L starts at levels[L].offset, tile (face, x, y) is at index (face * n + y) * n + x with n = 2^L
  <out>.json  tile_size, max_level, level offsets, ...

Usage (from the project root):
  tools/.venv/bin/python tools/bake_tiles.py data/etopo_30s data/earth_tiles --max-level 7
"""

import argparse
import json
import time
from pathlib import Path

import numpy as np

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
    assert info["format"] == "int16_le_meters"
    data = np.fromfile(args.input.with_suffix(".bin"), dtype="<i2").reshape(info["height"], info["width"]).astype(np.float32)

    step = args.tile_size - 1
    tile_bytes = args.tile_size * args.tile_size * 2
    levels = []
    offset = 0
    for level in range(args.max_level + 1):
        levels.append({"level": level, "offset": offset})
        offset += 6 * (1 << level) ** 2 * tile_bytes
    total_bytes = offset

    face_pixels = (1 << args.max_level) * step  # last pixel index of a face at the finest level
    out = np.memmap(args.output.with_suffix(".bin"), dtype="<i2", mode="w+", shape=(total_bytes // 2,))

    start = time.time()
    for face in range(6):
        finest = np.empty((face_pixels + 1, face_pixels + 1), dtype=np.int16)
        cols = np.arange(face_pixels + 1, dtype=np.float64) / face_pixels
        for row_start in range(0, face_pixels + 1, 256):
            rows = np.arange(row_start, min(row_start + 256, face_pixels + 1), dtype=np.float64) / face_pixels
            u, v = np.meshgrid(cols, rows)
            meters = sample_equirect(data, *face_to_sphere(face, u, v))
            finest[row_start:row_start + len(rows)] = np.clip(np.rint(meters), -32768, 32767)

        for level in range(args.max_level + 1):
            n = 1 << level
            grid = finest[::1 << (args.max_level - level), ::1 << (args.max_level - level)]  # every 2^k-th pixel
            for tile_y in range(n):
                for tile_x in range(n):
                    tile = grid[tile_y * step:tile_y * step + args.tile_size, tile_x * step:tile_x * step + args.tile_size]
                    index = (face * n + tile_y) * n + tile_x
                    begin = (levels[level]["offset"] + index * tile_bytes) // 2
                    out[begin:begin + tile.size] = tile.ravel()
        print(f"face {face} done ({time.time() - start:.0f} s)")

    out.flush()
    meta = {
        "format": "int16_le_meters",
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
