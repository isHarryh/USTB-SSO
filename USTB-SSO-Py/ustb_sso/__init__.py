from . import _exceptions as exceptions
from . import _prefabs as prefabs

try:
    from ._auth_session import HttpxAuthSession
except ImportError:
    pass

_all_impl = ('HttpxAuthSession',)

if all(i not in globals() for i in _all_impl):
    raise ImportError(
        f"None of these implementations is available: {_all_impl}"
        + " , you may install httpx lib."
    )
