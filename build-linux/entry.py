"""PyInstaller entry point.

cli.py uses package-relative imports (from .core import ...), so it
cannot be pointed to directly as a PyInstaller script; this thin entry
point imports the package normally instead."""

import sys

from sbusta_p7m.cli import main

if __name__ == "__main__":
    sys.exit(main())
