# TYPE:        script
# SCOPE:       sbusta-p7m
# VERSION:     0.1.1
# DESCRIPTION: PyInstaller entry point for the self-contained macOS CLI binary
# NAME:        entry.py

# changelog:
# 0.1.1 - project renamed from p7m-reader to sbusta-p7m (the tool
#         unpacks/extracts, it doesn't "read" .p7m files)
# 0.1.0 - initial implementation

"""PyInstaller entry point.

cli.py uses package-relative imports (from .core import ...), so it
cannot be pointed to directly as a PyInstaller script; this thin entry
point imports the package normally instead."""

import sys

from sbusta_p7m.cli import main

if __name__ == "__main__":
    sys.exit(main())
