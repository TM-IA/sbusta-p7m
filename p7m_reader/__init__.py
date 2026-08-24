# TYPE:        script
# SCOPE:       p7m-reader
# VERSION:     0.1.0
# DESCRIPTION: package entry point, re-exports the public core API
# NAME:        __init__.py

# changelog:
# 0.1.0 - initial implementation

from .core import estrai, P7mError, P7mFormatError, P7mContentError

__all__ = ["estrai", "P7mError", "P7mFormatError", "P7mContentError"]
