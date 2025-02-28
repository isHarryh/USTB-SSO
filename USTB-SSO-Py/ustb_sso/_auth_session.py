from typing import Generic, Optional, TypeVar
from typing_extensions import override, Self

import re
import time
from urllib.parse import parse_qs, unquote, urlparse
from html import unescape

from ._exceptions import (
    APIError,
    BadResponseError,
    IllegalStateError,
    TimeoutError,
    UnsupportedMethodError
)

_T_CLI = TypeVar("_T_CLI")
_T_RSP = TypeVar("_T_RSP")


class AuthSessionBase(Generic[_T_CLI, _T_RSP]):
    _SSO_AUTH_ENTRY = "https://sso.ustb.edu.cn/idp/authCenter/authenticate"
    _SSO_QR_INFO = "https://sso.ustb.edu.cn/idp/authn/getMicroQr"
    _SIS_QR_PAGE = "https://sis.ustb.edu.cn/connect/qrpage"
    _SIS_QR_IMG = "https://sis.ustb.edu.cn/connect/qrimg"
    _SIS_QR_STATE = "https://sis.ustb.edu.cn/connect/state"
    QR_CODE_TIMEOUT = 180
    POLLING_TIMEOUT = 16

    _client: _T_CLI
    _entity_id: str
    _redirect_uri: str
    _state: str
    _lck: Optional[str]
    _app_id: Optional[str]
    _return_url: Optional[str]
    _random_token: Optional[str]
    _sid: Optional[str]

    def __init__(
        self,
        entity_id: str,
        redirect_uri: str,
        state: str = "ustb",
        client: Optional[_T_CLI] = None
    ):
        """Initializes a USTB SSO authentication session.

        :param entity_id: The application's entity id;
        :param redirect_uri: The redirection URI to the authentication destination;
        :param state: The internal state of the application;
        :param client: The optional networking client, leave `None` to create a new one;
        """
        self._client = self._new_client() if not client else client
        self._entity_id = entity_id
        self._redirect_uri = redirect_uri
        self._state = state

        self._lck = None
        self._app_id = None
        self._return_url = None
        self._random_token = None
        self._sid = None

    def _get(self, url: str, redirect: bool = False, **kwargs) -> _T_RSP:
        raise NotImplementedError()

    def _post(self, url: str, redirect: bool = False, **kwargs) -> _T_RSP:
        raise NotImplementedError()

    def _dict(self, rsp: _T_RSP) -> dict:
        raise NotImplementedError()

    def _new_client(self) -> _T_CLI:
        raise NotImplementedError()

    @property
    def client(self) -> _T_CLI:
        """Gets the networking client.
        """
        return self._client

    def open_auth(self) -> Self:
        """Initiates the authentication workflow.
        """
        rsp = self._get(
            AuthSessionBase._SSO_AUTH_ENTRY,
            params={
                "client_id": self._entity_id,
                "redirect_uri": self._redirect_uri,
                "login_return": "true",
                "state": self._state,
                "response_type": "code"
            },
            redirect=False
        )

        if rsp.status_code // 100 != 3:
            raise APIError(f"HTTP status code: {rsp.status_code}, expected 3xx")

        location = rsp.headers.get("Location")
        if not location:
            raise BadResponseError("Missing \"Location\" header in response")

        qs = parse_qs(urlparse(location.replace("/#/", "/")).query)
        self._lck = qs.get("lck", [None])[0]
        if not self._lck:
            raise BadResponseError("Failed to extract \"lck\" from Location header")

        return self

    def use_wechat_auth(self) -> Self:
        """Prepares WeChat authentication info.
        """
        if not self._lck:
            raise IllegalStateError("Authentication not initiated. Call `open_auth` first.")

        rsp = self._post(
            self._SSO_QR_INFO,
            json={
                "entityId": self._entity_id,
                "lck": self._lck
            }
        )

        data = self._dict(rsp)

        if data.get("code") != "200":
            raise APIError(f"API code {data.get('code')}: {data.get('message', '')}")

        try:
            self._app_id = data["data"]["appId"]
            self._return_url = data["data"]["returnUrl"]
            self._random_token = data["data"]["randomToken"]
        except KeyError as e:
            raise BadResponseError(f"Missing key in response") from e

        return self

    def use_qr_code(self) -> Self:
        """Prepares QR code SID from QR page.
        """
        if any(not i for i in (self._app_id, self._return_url, self._random_token)):
            raise IllegalStateError("Not in WeChat mode yet. Call `use_wechat_auth` first.")

        rsp = self._get(
            self._SIS_QR_PAGE,
            params={
                "appid": self._app_id,
                "return_url": self._return_url,
                "rand_token": self._random_token,
                "embed_flag": "1"
            }
        )

        if rsp.status_code != 200:
            raise APIError(f"HTTP status code {rsp.status_code}, expected 200")

        match = re.search(r"sid\s?=\s?(\w{32})", rsp.text)
        if not match:
            raise BadResponseError("SID not found in QR page")
        self._sid = match.group(1)

        return self

    def get_qr_image(self) -> bytes:
        """Downloads QR code image and returns it in bytes.
        """
        if not self._sid:
            raise IllegalStateError("SID not available. Call `use_qr_code` first.")

        rsp = self._get(
            self._SIS_QR_IMG,
            params={"sid": self._sid}
        )

        if rsp.status_code != 200:
            raise APIError(
                f"QR image request failed with HTTP status code {rsp.status_code}"
            )

        return rsp.content

    def wait_for_pass_code(self) -> str:
        """Polls the authentication status until completion or timeout.

        Returns the pass code if completed. Raises exception when timed out.
        """
        if not self._sid:
            raise IllegalStateError("SID not available. Call `use_qr_code` first.")

        start_time = time.time()
        while time.time() - start_time < self.QR_CODE_TIMEOUT:
            try:
                rsp = self._get(
                    self._SIS_QR_STATE,
                    params={
                        "sid": self._sid
                    },
                    timeout=self.POLLING_TIMEOUT
                )
            except Exception:
                time.sleep(1)
                continue

            data = self._dict(rsp)

            code = data.get("code")
            if code == 1:  # Success
                return data["data"]
            elif code in (3, 202):  # Expired
                raise TimeoutError("QR code expired")
            elif code == 4:  # Timeout
                continue
            elif code in (101, 102):  # Invalid
                raise APIError(f"API code {code}: {data.get('message', '')}")

        raise TimeoutError("Authentication polling timed out")

    def complete_auth(self, pass_code: str) -> _T_RSP:
        """Completes authentication workflow.
        """
        if any(not i for i in (self._app_id, self._return_url, self._random_token)):
            raise IllegalStateError("Authentication not well established")

        params = {
            "appid": self._app_id,
            "auth_code": pass_code,
            "rand_token": self._random_token
        }
        params.update(parse_qs(urlparse(self._return_url).query))

        rsp = self._get(
            self._return_url,
            params=params,
            redirect=True
        )

        action_type_match = re.search(r'var actionType\s*=\s*"([^"]+)"', rsp.text)
        location_value_match = re.search(r'var locationValue\s*=\s*"([^"]+)"', rsp.text)
        if action_type_match and location_value_match:
            action_type = unescape(unquote(action_type_match.group(1)))
            location_value = unescape(unquote(location_value_match.group(1)))
        else:
            raise BadResponseError("Failed to get authentication destination")

        if action_type.upper() != "GET":
            raise UnsupportedMethodError("Unsupported authentication destination method")

        rsp_ = self._get(
            location_value,
            redirect=True
        )

        return rsp_


try:
    import httpx

    class HttpxAuthSession(AuthSessionBase[httpx.Client, httpx.Response]):
        @override
        def _get(self, url: str, redirect: bool = False, **kwargs) -> httpx.Response:
            return self._client.get(url, follow_redirects=redirect, **kwargs)

        @override
        def _post(self, url: str, redirect: bool = False, **kwargs) -> httpx.Response:
            return self._client.post(url, follow_redirects=redirect, **kwargs)

        @override
        def _dict(self, rsp: httpx.Response) -> dict:
            if rsp.status_code != 200:
                raise APIError(
                    f"HTTP status code: {rsp.status_code}, expected 200"
                )

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
