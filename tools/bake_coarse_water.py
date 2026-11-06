"""Rebuilds the coarse levels of the baked height and water tiles from the finest level, so lakes and coasts keep
their size from far away. Run after bake_tiles.py for both, it changes the files in place (the finest level stays).

Point sampling (every second pixel) made one coarse water pixel carry a small lake's level over a huge area,
or miss a big lake. Here a coarse height pixel is water if at least half of what it covers is wet, the water level
is the mean of the wet ones, and the height gets pushed MARGIN under / over the water so the shore follows that.

Usage (from the project root):
  tools/.venv/bin/python tools/bake_coarse_water.py data/earth_tiles data/earth_water
"""

import argparse
import json
import time
from pathlib import Path

import numpy as np
import scipy.ndimage as nd

MARGIN = 2.0  # meters


def tent_axis0(a):
    # Pixels are shared corners: coarse pixel i is fine pixel 2i, its neighbours weigh half.
    # The face border only along the border, so neighbouring faces get the same values there
    m = (a.shape[0] - 1) // 2
    out = np.empty((m + 1,) + a.shape[1:], dtype=a.dtype)
    out[1:m] = 0.25 * a[1:2 * m - 1:2] + 0.5 * a[2:2 * m:2] + 0.25 * a[3:2 * m + 1:2]
    out[0] = a[0]
    out[m] = a[2 * m]
    return out


def tent(a):
    return tent_axis0(tent_axis0(a).T).T


def min_axis0(a):
    m = (a.shape[0] - 1) // 2
    out = np.empty((m + 1,) + a.shape[1:], dtype=a.dtype)
    out[1:m] = np.minimum(np.minimum(a[1:2 * m - 1:2], a[2:2 * m:2]), a[3:2 * m + 1:2])
    out[0] = a[0]
    out[m] = a[2 * m]
    return out


def min_pool(a):
    return min_axis0(min_axis0(a).T).T


def upsample(a, factor):
    # bilinear, corners stay on corners like the game's sampling
    return nd.zoom(a, ((a.shape[0] - 1) * factor + 1) / a.shape[0], order=1, grid_mode=False)


class Tiles:
    def __init__(self, path):
        self.info = json.loads(path.with_suffix(".json").read_text())
        self.size = self.info["tile_size"]
        self.max_level = self.info["max_level"]
        self.data = np.memmap(path.with_suffix(".bin"), dtype="<i2", mode="r+")
        self.offsets = [entry["offset"] // 2 for entry in self.info["levels"]]

    def tile_slices(self, face, level):
        n = 1 << level
        step = self.size - 1
        for ty in range(n):
            for tx in range(n):
                begin = self.offsets[level] + ((face * n + ty) * n + tx) * self.size * self.size
                yield slice(begin, begin + self.size * self.size), (slice(ty * step, ty * step + self.size), slice(tx * step, tx * step + self.size))

    def read_face(self, face, level):
        edge = (self.size - 1) * (1 << level) + 1
        grid = np.empty((edge, edge), dtype=np.float32)
        for flat, box in self.tile_slices(face, level):
            grid[box] = self.data[flat].reshape(self.size, self.size)
        return grid

    def write_face(self, face, level, grid):
        values = np.clip(np.rint(grid), -32768, 32767).astype("<i2")
        for flat, box in self.tile_slices(face, level):
            self.data[flat] = values[box].ravel()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("heights", type=Path, help="baked height tiles without extension")
    parser.add_argument("water", type=Path, help="baked water tiles without extension")
    args = parser.parse_args()

    heights = Tiles(args.heights)
    water = Tiles(args.water)
    top = heights.max_level
    assert water.max_level == top
    ratio = (heights.size - 1) // (water.size - 1)
    pools = ratio.bit_length() - 1  # water grid is this many halvings coarser than the heights
    assert 1 << pools == ratio

    start = time.time()
    for face in range(6):
        fine_heights = heights.read_face(face, top)
        fine_water = water.read_face(face, top)

        water_up = upsample(fine_water, ratio)
        wet = (water_up > fine_heights).astype(np.float32)
        level_sum = water_up * wet
        del water_up
        # index j: heights resolution of level j, j < 0 for the water of level 0 and 1
        wet_share = {top: wet}
        wet_levels = {top: level_sum}
        for j in range(top - 1, -pools - 1, -1):
            wet_share[j] = tent(wet_share[j + 1])
            wet_levels[j] = tent(wet_levels[j + 1])
        del wet, level_sum
        lowest = {top - pools: fine_water}
        for j in range(top - pools - 1, -pools - 1, -1):
            lowest[j] = min_pool(lowest[j + 1])

        for level in range(top):
            is_wet = wet_share[level] >= 0.5
            level_sum = np.where(is_wet, wet_levels[level] / np.maximum(wet_share[level], 1e-6), 0.0).astype(np.float32)
            share = is_wet.astype(np.float32)
            for _ in range(pools):
                share = tent(share)
                level_sum = tent(level_sum)
            has_water = share > 0
            coarse_water = np.where(has_water, level_sum / np.maximum(share, 1e-6), lowest[level - pools])

            # one pixel around the water gets its level too, not on the face border (the other face can't see it)
            spread = nd.maximum_filter(np.where(has_water, coarse_water, -np.inf), size=3)
            around = ~has_water & np.isfinite(spread)
            around[0, :] = around[-1, :] = around[:, 0] = around[:, -1] = False
            coarse_water[around] = spread[around]

            water_at_heights = upsample(coarse_water.astype(np.float32), ratio)
            step = 1 << (top - level)
            coarse_heights = fine_heights[::step, ::step]
            coarse_heights = np.where(is_wet, np.minimum(coarse_heights, water_at_heights - MARGIN),
                                      np.maximum(coarse_heights, water_at_heights + MARGIN))
            heights.write_face(face, level, coarse_heights)
            water.write_face(face, level, coarse_water)
        print(f"face {face} done ({time.time() - start:.0f} s)")

    heights.data.flush()
    water.data.flush()


if __name__ == "__main__":
    main()
