from typing import Generic, Optional, TypeVar, override

_T_CLI = TypeVar("_T_CLI")
_T_RSP = TypeVar("_T_RSP")


class SessionBase(Generic[_T_CLI, _T_RSP]):
    """Base class for HTTP session management."""

    _client: _T_CLI

    def __init__(self, client: Optional[_T_CLI] = None):
        """Initializes a session.

        :param client: The optional networking client, leave `None` to create a new one;
        """
        self._client = self._new_client() if not client else client

    def _get(self, url: str, redirect: bool = False, **kwargs) -> _T_RSP:
        """Performs a GET request."""
        raise NotImplementedError()

    def _post(self, url: str, redirect: bool = False, **kwargs) -> _T_RSP:
        """Performs a POST request."""
        raise NotImplementedError()

    def _dict(self, rsp: _T_RSP) -> dict:
        """Converts response to dictionary."""
        raise NotImplementedError()

    def _new_client(self) -> _T_CLI:
        """Creates a new client instance."""
        raise NotImplementedError()

    @property
    def client(self) -> _T_CLI:
        """Gets the networking client."""
        return self._client


try:
    import httpx
    from ._exceptions import APIError, BadResponseError

    class HttpxSession(SessionBase[httpx.Client, httpx.Response]):
        """HTTP session implementation using httpx."""

        @override
        def _get(self, url: str, redirect: bool = False, **kwargs) -> httpx.Response:
            return self._client.get(url, follow_redirects=redirect, **kwargs)

        @override
        def _post(self, url: str, redirect: bool = False, **kwargs) -> httpx.Response:
            return self._client.post(url, follow_redirects=redirect, **kwargs)

        @override
        def _dict(self, rsp: httpx.Response) -> dict:
            if rsp.status_code != 200:
                raise APIError(f"HTTP status code: {rsp.status_code}, expected 200")

            try:
                data = rsp.json()
                if not isinstance(data, dict):
                    raise TypeError("Not a dict")
                return data
            except Exception as e:
                raise BadResponseError("Invalid JSON response") from e

        @override
        def _new_client(self):
            return httpx.Client()

except ImportError:
    pass
