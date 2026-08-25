# TYPE:        script
# SCOPE:       sbusta-p7m
# VERSION:     0.1.1
# DESCRIPTION: package entry point, re-exports the public core API
# NAME:        __init__.py

# changelog:
# 0.1.1 - project renamed from p7m-reader to sbusta-p7m (the tool
#         unpacks/extracts, it doesn't "read" .p7m files)
# 0.1.0 - initial implementation

from .core import estrai, P7mError, P7mFormatError, P7mContentError

__all__ = ["estrai", "P7mError", "P7mFormatError", "P7mContentError"]
