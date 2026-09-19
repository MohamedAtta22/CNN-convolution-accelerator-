#!/usr/bin/env python3

import argparse
import sys
from pathlib import Path

import numpy as np


def to_hex_byte(value: int) -> str:
    return format(value & 0xFF, "02x")


def to_hex_halfword(value: int) -> str:
    return format(value & 0xFFFF, "04x")


def compute_expected(image: np.ndarray, kernel: np.ndarray, relu_enable: bool) -> np.ndarray:
    h, w = image.shape
    n = kernel.shape[0]
    out_h, out_w = h - n + 1, w - n + 1
    out = np.zeros((out_h, out_w), dtype=np.int64)

    img = image.astype(np.int64)
    ker = kernel.astype(np.int64)

    for r in range(out_h):
        for c in range(out_w):
            window = img[r:r + n, c:c + n]
            acc = int(np.sum(window * ker))
            if relu_enable and acc < 0:
                acc = 0
            elif acc > 32767:
                acc = 32767
            elif acc < -32768:
                acc = -32768
            out[r, c] = acc

    return out


def cmd_generate(args):
    rng = np.random.default_rng(args.seed)

    w, h, n = args.width, args.height, args.kernel_size
    if n < 1 or n > min(w, h):
        sys.exit(f"kernel-size {n} must be between 1 and min(width, height)={min(w, h)}")

    image = rng.integers(0, 256, size=(h, w), dtype=np.int64)          # unsigned 8-bit
    kernel = rng.integers(-128, 128, size=(n, n), dtype=np.int64)      # signed 8-bit

    expected = compute_expected(image, kernel, bool(args.relu))

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    # image.hex: row-major, one byte per line, matches the order pixels
    # are streamed into pixel_in (row 0 col 0 first)
    with open(outdir / "image.hex", "w") as f:
        for r in range(h):
            for c in range(w):
                f.write(to_hex_byte(int(image[r, c])) + "\n")

    # kernel.hex: address order 0..N*N-1 = row-major (kr*N + kc), matching
    # kernel_memory's addressing
    with open(outdir / "kernel.hex", "w") as f:
        for r in range(n):
            for c in range(n):
                f.write(to_hex_byte(int(kernel[r, c])) + "\n")

    # expected_output.hex: row-major over the output grid, matching the
    # DUT's output_row/output_col streaming order
    with open(outdir / "expected_output.hex", "w") as f:
        for r in range(expected.shape[0]):
            for c in range(expected.shape[1]):
                f.write(to_hex_halfword(int(expected[r, c])) + "\n")

    # config.hex: single line, relu_enable as 0/1, so the testbench doesn't
    # need a manually-kept-in-sync parameter
    with open(outdir / "config.hex", "w") as f:
        f.write("1\n" if args.relu else "0\n")

    # Also dump a human-readable copy for sanity-checking
    with open(outdir / "summary.txt", "w") as f:
        f.write(f"image: {w}x{h}\n")
        f.write(f"kernel: {n}x{n}\n")
        f.write(f"relu_enable: {bool(args.relu)}\n")
        f.write(f"seed: {args.seed}\n")
        f.write(f"output: {expected.shape[1]}x{expected.shape[0]}\n")
        f.write("\nkernel coefficients:\n")
        f.write(np.array2string(kernel) + "\n")

    print(f"Wrote {w*h} pixels, {n*n} kernel taps, "
        f"{expected.shape[0]*expected.shape[1]} expected outputs to {outdir}/")
    print(f"(relu_enable={bool(args.relu)}, seed={args.seed})")


def cmd_compare(args):
    outdir = Path(args.outdir)
    expected_path = outdir / "expected_output.hex"
    actual_path = Path(args.actual)

    expected = [int(line.strip(), 16) for line in open(expected_path) if line.strip()]
    actual_raw = [int(line.strip(), 16) for line in open(actual_path) if line.strip()]

    def to_signed16(v):
        return v - 0x10000 if v & 0x8000 else v

    expected_s = [to_signed16(v) for v in expected]
    actual_s = [to_signed16(v) for v in actual_raw]

    if len(expected_s) != len(actual_s):
        print(f"FAIL: expected {len(expected_s)} outputs, got {len(actual_s)}")
        sys.exit(1)

    mismatches = [
        (i, e, a) for i, (e, a) in enumerate(zip(expected_s, actual_s)) if e != a
    ]

    print(f"Compared {len(expected_s)} outputs against {expected_path}")
    if not mismatches:
        print("PASS: Vivado/RTL simulation output matches the Python golden model exactly.")
    else:
        print(f"FAIL: {len(mismatches)} mismatch(es):")
        for i, e, a in mismatches[:20]:
            print(f"  [{i}] expected={e} actual={a}")
        if len(mismatches) > 20:
            print(f"  ... and {len(mismatches) - 20} more")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("generate", help="Generate test vectors + expected output")
    g.add_argument("--width", type=int, default=32)
    g.add_argument("--height", type=int, default=32)
    g.add_argument("--kernel-size", type=int, default=3)
    g.add_argument("--relu", type=int, choices=[0, 1], default=0)
    g.add_argument("--seed", type=int, default=1234)
    g.add_argument("--outdir", type=str, default="vectors")
    g.set_defaults(func=cmd_generate)

    c = sub.add_parser("compare", help="Compare a simulation's actual output against the golden model")
    c.add_argument("--outdir", type=str, default="vectors", help="Directory holding expected_output.hex")
    c.add_argument("--actual", type=str, required=True, help="Path to actual_output.hex from simulation")
    c.set_defaults(func=cmd_compare)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
