#!/usr/bin/env python3
"""Fail when the compiled DamaCore contract differs from its SSOT source."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = REPOSITORY_ROOT / "ssot/contracts/DomainContracts.swift"
DEFAULT_DERIVED = (
    REPOSITORY_ROOT / "Packages/DamaCore/Sources/DamaCore/DomainContracts.swift"
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--derived", type=Path, default=DEFAULT_DERIVED)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    source = arguments.source.resolve()
    derived = arguments.derived.resolve()

    missing = [path for path in (source, derived) if not path.is_file()]
    if missing:
        for path in missing:
            print(f"ERROR missing contract file: {path}")
        return 1

    source_bytes = source.read_bytes()
    derived_bytes = derived.read_bytes()
    if source_bytes != derived_bytes:
        print("ERROR DamaCore contract copy drifted from SSOT")
        print(f"  source : {source} ({hashlib.sha256(source_bytes).hexdigest()})")
        print(f"  derived: {derived} ({hashlib.sha256(derived_bytes).hexdigest()})")
        return 1

    digest = hashlib.sha256(source_bytes).hexdigest()
    print(f"PASS contract copy: {len(source_bytes)} bytes, sha256={digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
