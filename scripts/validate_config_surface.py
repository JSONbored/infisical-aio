#!/usr/bin/env python3
from __future__ import annotations

import sys

from config_surface import collect_validation_errors


def main() -> int:
    errors = collect_validation_errors()
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("config_surface.toml passed upstream, runtime, and bootstrap drift checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
