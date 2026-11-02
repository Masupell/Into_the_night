"""Converts the Global Aridity Index (Zomer & Trabucco, v3.1, CC BY 4.0) into a moisture map.

Aridity index = yearly rain / potential evaporation, turned into 0 desert .. 1 rainforest (see AI_TO_MOISTURE).
Sea and everything below 60S are filled from the land around them.

Output:
  <out>.bin   uint8, moisture * 255, same layout as ETOPO
  <out>.json  width, height, format and where the data came from

Usage (from the project root):
  tools/.venv/bin/python tools/convert_aridity.py data/source/ai_v31_yr.tif data/moisture_60s --downsample 2
"""

import argparse
import json
from pathlib import Path

import numpy as np
import tifffile

# Aridity index -> moisture, linear in between
AI_TO_MOISTURE = (
    (0.0, 0.0),
    (0.03, 0.05),  # hyper-arid: full desert
    (0.2, 0.2),  # arid: desert edge
    (0.5, 0.38),  # semi-arid: savanna / steppe
    (0.65, 0.5),  # dry sub-humid: plain grass
    (1.0, 0.62),
    (1.5, 0.8),  # forest
    (2.5, 1.0),  # rainforest
)

FULL_HEIGHT_ROWS_PER_DEGREE = 120  # 30 arc seconds


def upsample2(a):
    """Twice the size, bilinear"""
    for axis in (0, 1):
        p = np.pad(a, [(1, 1) if i == axis else (0, 0) for i in range(2)], mode="edge")
        mid = np.take(p, range(1, p.shape[axis] - 1), axis=axis)
        before = np.take(p, range(0, p.shape[axis] - 2), axis=axis)
        after = np.take(p, range(2, p.shape[axis]), axis=axis)
        out = np.empty([s * 2 if i == axis else s for i, s in enumerate(a.shape)], dtype=np.float32)
        index = [slice(None), slice(None)]
        index[axis] = slice(0, None, 2)
        out[tuple(index)] = 0.75 * mid + 0.25 * before
        index[axis] = slice(1, None, 2)
        out[tuple(index)] = 0.75 * mid + 0.25 * after
        a = out
    return a


def fill_gaps(values, valid):
    """Push-pull fill of the invalid pixels"""
    if valid.all():
        return values
    h, w = values.shape
    ph, pw = h + h % 2, w + w % 2
    v = np.pad(values * valid, ((0, ph - h), (0, pw - w)), mode="edge")
    m = np.pad(valid.astype(np.float32), ((0, ph - h), (0, pw - w)), mode="edge")
    weight = m.reshape(ph // 2, 2, pw // 2, 2).sum(axis=(1, 3))
    total = v.reshape(ph // 2, 2, pw // 2, 2).sum(axis=(1, 3))
    coarse_valid = weight > 0
    coarse = np.where(coarse_valid, total / np.maximum(weight, 1e-9), 0.0).astype(np.float32)
    coarse = fill_gaps(coarse, coarse_valid)
    up = upsample2(coarse)[:h, :w]
    return np.where(valid, values, up)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path, help="ai_v31_yr.tif (aridity index * 10000, uint16)")
    parser.add_argument("output", type=Path, help="output path without extension")
    parser.add_argument("--downsample", type=int, default=2, help="averages NxN pixels (2: 60 arc seconds)")
    args = parser.parse_args()

    raw = tifffile.imread(args.input)
    print(f"read {args.input.name}: {raw.shape[1]} x {raw.shape[0]}")
    # The file stops at 60S
    full_rows = 180 * FULL_HEIGHT_ROWS_PER_DEGREE
    assert raw.shape[1] == 360 * FULL_HEIGHT_ROWS_PER_DEGREE and raw.shape[0] <= full_rows
    valid = np.zeros((full_rows, raw.shape[1]), dtype=bool)
    valid[:raw.shape[0]] = raw > 0  # 0 = sea / no data
    ai = np.zeros(valid.shape, dtype=np.float32)
    ai[:raw.shape[0]] = raw / 10000.0
    del raw

    if args.downsample > 1:  # only valid pixels, so coasts don't go towards 0
        f = args.downsample
        h, w = ai.shape[0] // f, ai.shape[1] // f
        weight = valid[:h * f, :w * f].reshape(h, f, w, f).sum(axis=(1, 3))
        total = ai[:h * f, :w * f].reshape(h, f, w, f).sum(axis=(1, 3))
        valid = weight > 0
        ai = np.where(valid, total / np.maximum(weight, 1), 0.0).astype(np.float32)

    ai_points, moisture_points = zip(*AI_TO_MOISTURE)
    moisture = np.interp(ai, ai_points, moisture_points).astype(np.float32)
    print(f"land: {valid.mean() * 100:.0f} % of pixels, filling the rest")
    moisture = fill_gaps(moisture, valid)

    out = np.clip(np.rint(moisture * 255.0), 0, 255).astype(np.uint8)
    height, width = out.shape
    args.output.parent.mkdir(parents=True, exist_ok=True)
    out.tofile(args.output.with_suffix(".bin"))
    info = {
        "width": width,
        "height": height,
        "format": "uint8_moisture",
        "layout": "row 0 = 90N, column 0 = 180W, pixel centers, value / 255 = moisture",
        "source": args.input.name + " (Global Aridity Index v3.1, Zomer & Trabucco, CC BY 4.0)",
        "ai_to_moisture": AI_TO_MOISTURE,
        "downsample": args.downsample,
    }
    args.output.with_suffix(".json").write_text(json.dumps(info, indent=2) + "\n")
    print(f"wrote {args.output.with_suffix('.bin')}: {width} x {height}, {out.nbytes / 1e6:.0f} MB")


if __name__ == "__main__":
    main()
