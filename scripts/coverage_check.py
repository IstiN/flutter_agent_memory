#!/usr/bin/env python3
"""Coverage ratchet for lib/ and bin/.

Parses coverage/lcov.info and ensures that the line-coverage percentage for
code under lib/ and bin/ does not fall below the baseline.
"""

import os
import sys

BASELINE = 75.0
TARGET = 80.0


def main() -> int:
    lcov_path = "coverage/lcov.info"
    if not os.path.isfile(lcov_path):
        print(f"ERROR: {lcov_path} not found. Run: dart test --coverage=coverage")
        return 1

    with open(lcov_path, "r") as f:
        content = f.read()

    files = content.split("SF:")
    total_found = 0
    total_hit = 0

    for sec in files[1:]:
        lines = sec.strip().split("\n")
        sf_line = lines[0]
        path = sf_line[3:] if sf_line.startswith("SF:") else sf_line
        relpath = os.path.relpath(path)

        if not (relpath.startswith("lib/") or relpath.startswith("bin/")):
            continue

        for line in lines[1:]:
            if line.startswith("DA:"):
                total_found += 1
                if int(line[3:].split(",")[1]) > 0:
                    total_hit += 1

    if total_found == 0:
        print("ERROR: no coverage data for lib/ or bin/")
        return 1

    pct = (total_hit / total_found) * 100

    print(f"Coverage (lib/ + bin/): {total_hit}/{total_found} lines = {pct:.1f}%")

    if pct < BASELINE:
        print(f"FAILED: coverage {pct:.1f}% is below baseline {BASELINE}%")
        return 1

    print(f"OK: coverage {pct:.1f}% >= baseline {BASELINE}%")
    if pct >= TARGET:
        print(f"EXCELLENT: coverage target {TARGET}% reached!")
    else:
        print(f"TARGET: {TARGET}% (keep adding tests)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
