from . import _exceptions as exceptions
from . import _prefabs as prefabs

# Core new architecture classes
from ._sessions import SessionBase
from ._procedure import AuthProcedureBase, QrAuthProcedure

# Concrete implementations
try:
    from ._sessions import HttpxSession

    _has_httpx = True
except ImportError:
    _has_httpx = False

if not _has_httpx:
    raise ImportError("HttpX implementation not available. Please install httpx: pip install httpx")
