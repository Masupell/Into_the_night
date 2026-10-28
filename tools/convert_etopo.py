"""Converts an ETOPO 2022 GeoTIFF into a raw file Godot can read quickly.

Output (next to each other):
  <out>.bin   int16 little endian, elevation in meters relative to sea level, row major,
              row 0 = 90N (north), column 0 = 180W, pixel centers (same layout as the GeoTIFF)
  <out>.json  width, height, format and where the data came from

Usage (from the project root):
  tools/.venv/bin/python tools/convert_etopo.py data/source/ETOPO_2022_v1_30s_N90W180_surface.tif data/etopo_30s
  add --downsample 4 for a smaller test file (averages 4x4 pixels)
"""

import argparse
import json
from pathlib import Path

import numpy as np
import tifffile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path, help="output path without extension")
    parser.add_argument("--downsample", type=int, default=1)
    args = parser.parse_args()

    elevation = tifffile.imread(args.input).astype(np.float32)
    print(f"read {args.input.name}: {elevation.shape[1]} x {elevation.shape[0]}, "
          f"{elevation.min():.0f} m .. {elevation.max():.0f} m")

    if args.downsample > 1:
        f = args.downsample
        h, w = elevation.shape[0] // f * f, elevation.shape[1] // f * f
        elevation = elevation[:h, :w].reshape(h // f, f, w // f, f).mean(axis=(1, 3))

    meters = np.clip(np.rint(elevation), -32768, 32767).astype("<i2")
    height, width = meters.shape

    args.output.parent.mkdir(parents=True, exist_ok=True)
    meters.tofile(args.output.with_suffix(".bin"))
    info = {
        "width": width,
        "height": height,
        "format": "int16_le_meters",
        "layout": "row 0 = 90N, column 0 = 180W, pixel centers",
        "min_m": int(meters.min()),
        "max_m": int(meters.max()),
        "source": args.input.name,
        "downsample": args.downsample,
    }
    args.output.with_suffix(".json").write_text(json.dumps(info, indent=2) + "\n")
    print(f"wrote {args.output.with_suffix('.bin')}: {width} x {height}, {meters.nbytes / 1e6:.0f} MB")


if __name__ == "__main__":
    main()
