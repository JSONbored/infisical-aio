#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys

from config_surface import (
    collect_validation_errors,
    config_reference_path,
    render_config_reference,
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate the canonical infisical-aio configuration reference."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if the generated markdown does not match the current output file.",
    )
    args = parser.parse_args()

    errors = collect_validation_errors()
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    rendered = render_config_reference()
    output_path = config_reference_path()

    if args.check:
        existing = output_path.read_text() if output_path.exists() else ""
        if existing != rendered:
            print(
                f"{output_path} is out of date with the generated configuration reference. "
                "Run scripts/generate_config_surface_docs.py to refresh it.",
                file=sys.stderr,
            )
            return 1
        print(f"{output_path} matches the generated configuration reference")
        return 0

    output_path.write_text(rendered)
    print(f"Wrote {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
