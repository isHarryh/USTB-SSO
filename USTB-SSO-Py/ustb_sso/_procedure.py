from typing import Generic, Optional, TypeVar, Self, Tuple

import base64
import json
import re
import time
from urllib.parse import parse_qs, unquote, urlparse
from html import unescape

from ._exceptions import APIError, BadResponseError, IllegalStateError, TimeoutError, UnsupportedMethodError
from ._sessions import SessionBase
from ._data import AuthMethodsResponse, AuthMethod

_T_CLI = TypeVar("_T_CLI")
_T_RSP = TypeVar("_T_RSP")


class AuthProcedureBase(Generic[_T_CLI, _T_RSP]):
    """Base class for authentication procedures."""

    _SSO_AUTH_ENTRY = "https://sso.ustb.edu.cn/idp/authCenter/authenticate"
    _SSO_QUERY_AUTH_METHODS = "https://sso.ustb.edu.cn/idp/authn/queryAuthMethods"

    _session: SessionBase[_T_CLI, _T_RSP]
    _entity_id: str
    _redirect_uri: str
    _state: str

    _lck: Optional[str]
    """Login context key. Initialized after `open_auth` call."""

    _auth_methods: Optional[AuthMethodsResponse]
    """Allowed authentication methods. Initialized after `open_auth` call."""

    def __init__(
        self,
        entity_id: str,
        redirect_uri: str,
        state: str = "ustb",
        session: Optional[SessionBase[_T_CLI, _T_RSP]] = None,
    ):
        """Initializes an authentication procedure.

        :param entity_id: The application's entity id;
        :param redirect_uri: The redirection URI to the authentication destination;
        :param state: The internal state of the application;
        :param session: The session instance for HTTP operations;
        """
        if session is None:
            raise ValueError("Session instance is required")

        self._session = session
        self._entity_id = entity_id
        self._redirect_uri = redirect_uri
        self._state = state
        self._lck = None
        self._auth_methods = None

    @property
    def session(self) -> SessionBase[_T_CLI, _T_RSP]:
        """Gets the session instance."""
        return self._session

    @property
    def auth_methods(self) -> AuthMethodsResponse:
        """Gets the available authentication methods."""
        if not self.is_opened():
            raise IllegalStateError("Authentication not opened yet.")
        assert self._auth_methods is not None
        return self._auth_methods

    def open_auth(self) -> None:
        """Initiates the authentication workflow. Retrieves the `lck` and available authentication methods."""
        self._retrieve_auth_entry()
        self._retrieve_auth_methods()

    def is_opened(self) -> bool:
        """Checks if the authentication procedure is opened."""
        return self._lck is not None and self._auth_methods is not None

    def _complete_auth(self, rsp: _T_RSP) -> _T_RSP:
        text = getattr(rsp, "text", None)
        if not isinstance(text, str):
            raise BadResponseError("Response text is not a string")

        action_type_match = re.search(r'var actionType\s*=\s*"([^"]+)"', text)
        location_value_match = re.search(r'var locationValue\s*=\s*"([^"]+)"', text)

        if action_type_match and location_value_match:
            action_type = unescape(unquote(action_type_match.group(1)))
            location_value = unescape(unquote(location_value_match.group(1)))
        else:
            raise BadResponseError("Failed to get authentication destination")

        if action_type.upper() != "GET":
            raise UnsupportedMethodError("Unsupported authentication destination method")

        return self._session._get(location_value, redirect=True)

    def _retrieve_auth_entry(self) -> None:
        rsp = self._session._get(
            self._SSO_AUTH_ENTRY,
            params={
                "client_id": self._entity_id,
                "redirect_uri": self._redirect_uri,
                "login_return": "true",
                "state": self._state,
                "response_type": "code",
            },
            redirect=False,
        )

        if getattr(rsp, "status_code", 0) // 100 != 3:
            raise APIError(f"HTTP status code: {getattr(rsp, 'status_code', 'unknown')}, expected 3xx")

        headers = getattr(rsp, "headers", {})
        location = headers.get("Location")
        if not location:
            raise BadResponseError('Missing "Location" header in response')

        qs = parse_qs(urlparse(location.replace("/#/", "/")).query)
        self._lck = qs.get("lck", [None])[0]
        if not self._lck:
            raise BadResponseError('Failed to extract "lck" from Location header')

    def _retrieve_auth_methods(self) -> None:
        if self._lck is None:
            raise IllegalStateError("Authentication not opened yet.")
        assert self._lck is not None

        rsp = self._session._post(self._SSO_QUERY_AUTH_METHODS, json={"lck": self._lck, "entityId": self._entity_id})

        if getattr(rsp, "status_code", 0) != 200:
            raise APIError(f"Query auth methods failed with status code: {getattr(rsp, 'status_code', 'unknown')}")

        data = self._session._dict(rsp)
        if data.get("code") != 200:
            raise APIError(f"Query auth methods failed with code {data.get('code')}: {data.get('message', '')}")

        self._auth_methods = AuthMethodsResponse.from_dict(data)
        if not self._auth_methods:
            raise BadResponseError("Failed to parse auth methods response")

    def _get_auth_method_by_module_code(self, module_code: str) -> AuthMethod:
        """Get authentication method by module code."""
        if not self._auth_methods:
            raise IllegalStateError("Authentication methods not queried. Call `query_auth_methods` first.")

        return self._auth_methods.get_method_by_module_code(module_code)


class QrAuthProcedure(AuthProcedureBase[_T_CLI, _T_RSP]):
    """QR code authentication procedure implementation."""

    _SSO_QR_INFO = "https://sso.ustb.edu.cn/idp/authn/getMicroQr"
    _SIS_QR_PAGE = "https://sis.ustb.edu.cn/connect/qrpage"
    _SIS_QR_IMG = "https://sis.ustb.edu.cn/connect/qrimg"
    _SIS_QR_STATE = "https://sis.ustb.edu.cn/connect/state"
    QR_CODE_TIMEOUT = 180
    POLLING_TIMEOUT = 16

    _app_id: Optional[str]
    _return_url: Optional[str]
    _random_token: Optional[str]
    _sid: Optional[str]

    def __init__(
        self,
        entity_id: str,
        redirect_uri: str,
        state: str = "ustb",
        session: Optional[SessionBase[_T_CLI, _T_RSP]] = None,
    ):
        super().__init__(entity_id, redirect_uri, state, session)
        self._app_id = None
        self._return_url = None
        self._random_token = None
        self._sid = None

    def use_wechat_auth(self) -> Self:
        """Prepares WeChat authentication info."""
        if not self._lck:
            raise IllegalStateError("Authentication not initiated. Call `open_auth` first.")

        rsp = self._session._post(self._SSO_QR_INFO, json={"entityId": self._entity_id, "lck": self._lck})

        data = self._session._dict(rsp)
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
        """Prepares QR code SID from QR page."""
        if any(not i for i in (self._app_id, self._return_url, self._random_token)):
            raise IllegalStateError("Not in WeChat mode yet. Call `use_wechat_auth` first.")

        rsp = self._session._get(
            self._SIS_QR_PAGE,
            params={
                "appid": self._app_id,
                "return_url": self._return_url,
                "rand_token": self._random_token,
                "embed_flag": "1",
            },
        )

        if getattr(rsp, "status_code", 0) != 200:
            raise APIError(f"HTTP status code {getattr(rsp, 'status_code', 'unknown')}, expected 200")

        text = getattr(rsp, "text", "")
        match = re.search(r"sid\s?=\s?(\w{32})", text)
        if not match:
            raise BadResponseError("SID not found in QR page")
        self._sid = match.group(1)

        return self

    def get_qr_image(self) -> bytes:
        """Downloads QR code image and returns it in bytes."""
        if not self._sid:
            raise IllegalStateError("SID not available. Call `use_qr_code` first.")

        rsp = self._session._get(self._SIS_QR_IMG, params={"sid": self._sid})

        if getattr(rsp, "status_code", 0) != 200:
            raise APIError(f"QR image request failed with HTTP status code {getattr(rsp, 'status_code', 'unknown')}")

        content = getattr(rsp, "content", b"")
        return content

    def wait_for_pass_code(self) -> str:
        """Polls the authentication status until completion or timeout.

        Returns the pass code if completed. Raises exception when timed out.
        """
        if not self._sid:
            raise IllegalStateError("SID not available. Call `use_qr_code` first.")

        start_time = time.time()
        while time.time() - start_time < self.QR_CODE_TIMEOUT:
            try:
                rsp = self._session._get(self._SIS_QR_STATE, params={"sid": self._sid}, timeout=self.POLLING_TIMEOUT)
            except Exception:
                time.sleep(1)
                continue

            data = self._session._dict(rsp)

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
        """Completes authentication workflow."""
        if any(not i for i in (self._app_id, self._return_url, self._random_token)):
            raise IllegalStateError("Authentication not well established")

        params = {"appid": self._app_id, "auth_code": pass_code, "rand_token": self._random_token}

        # Safe handling of return_url parsing
        if self._return_url:
            query_params = parse_qs(urlparse(self._return_url).query)
            # Convert list values to single values for the params dict
            for key, value_list in query_params.items():
                if value_list:
                    params[key] = value_list[0]

        if not self._return_url:
            raise IllegalStateError("Return URL not available")

        rsp = self._session._get(self._return_url, params=params, redirect=True)

        return self._complete_auth(rsp)


class SmsAuthProcedure(AuthProcedureBase[_T_CLI, _T_RSP]):
    """SMS authentication procedure implementation."""

    _SSO_CAPTCHA_CHECK = "https://sso.ustb.edu.cn/idp/captcha/checkOpen"
    _SSO_CAPTCHA_PUZZLE = "https://sso.ustb.edu.cn/idp/captcha/getBlockPuzzle"
    _SSO_SMS_SEND = "https://sso.ustb.edu.cn/idp/authn/sendSmsMsg"
    _SSO_AUTH_EXECUTE = "https://sso.ustb.edu.cn/idp/authn/authExecute"
    _SSO_AUTH_ENGINE = "https://sso.ustb.edu.cn/idp/authCenter/authnEngine?locale=zh-CN"

    def __init__(
        self,
        entity_id: str,
        redirect_uri: str,
        state: str = "ustb",
        session: Optional[SessionBase[_T_CLI, _T_RSP]] = None,
    ):
        super().__init__(entity_id, redirect_uri, state, session)

    def check_sms_available(self) -> Self:
        """Check if SMS authentication is available."""
        if not self._auth_methods:
            raise IllegalStateError("Authentication methods not queried. Call `open_auth` first.")

        # Check if SMS authentication method is available
        sms_method = self._get_auth_method_by_module_code("userAndSms")
        if not sms_method:
            raise APIError("SMS authentication method is not available for this entity")

        # Additional check via the captcha endpoint
        rsp = self._session._get(self._SSO_CAPTCHA_CHECK, params={"type": "sms"})

        if getattr(rsp, "status_code", 0) != 200:
            raise APIError(f"SMS check failed with status code: {getattr(rsp, 'status_code', 'unknown')}")

        return self

    def _get_captcha(self) -> Tuple[str, str, str]:
        """Get captcha puzzle."""
        rsp = self._session._get(self._SSO_CAPTCHA_PUZZLE)

        if getattr(rsp, "status_code", 0) != 200:
            raise APIError(f"Captcha puzzle request failed with status code: {getattr(rsp, 'status_code', 'unknown')}")

        data = self._session._dict(rsp)

        try:
            captcha_data = data["data"]
            original_image = captcha_data["originalImageBase64"]
            jigsaw_image = captcha_data["jigsawImageBase64"]
            token = captcha_data["token"]

            return original_image, jigsaw_image, token

        except KeyError as e:
            raise BadResponseError(f"Missing captcha data in response: {e}") from e

    def _solve_captcha(self, original_image_base64: str, jigsaw_image_base64: str) -> Tuple[int, int]:
        """Solve captcha using no_puzzle_captcha library."""
        try:
            from no_puzzle_captcha import PuzzleCaptchaSolver
        except ImportError:
            raise ImportError("no_puzzle_captcha library is required. Install with: pip install no_puzzle_captcha")

        original_image_data = base64.b64decode(original_image_base64)
        jigsaw_image_data = base64.b64decode(jigsaw_image_base64)

        solver = PuzzleCaptchaSolver()
        result = solver.handle_bytes(original_image_data, jigsaw_image_data)

        return result.x, result.y

    def send_sms(self, phone_number: str) -> Self:
        """Send SMS verification code."""
        if not self._lck:
            raise IllegalStateError("Authentication not initiated. Call `open_auth` first.")

        original_image, jigsaw_image, token = self._get_captcha()
        x, _ = self._solve_captcha(original_image, jigsaw_image)

        # Prepare SMS request data
        sms_data = {
            "loginName": phone_number,
            "pointJson": json.dumps({"x": x - 5, "y": 5}, separators=(",", ":")),
            "token": token,
            "lck": self._lck,
        }

        rsp = self._session._post(self._SSO_SMS_SEND, json=sms_data)

        if getattr(rsp, "status_code", 0) != 200:
            raise APIError(f"SMS send request failed with status code: {getattr(rsp, 'status_code', 'unknown')}")

        data = self._session._dict(rsp)

        data_data = data.get("data", {})
        # code: str, message: str, ...
        # (201 发送间隔过短, 5054 图形验证不通过, 200 成功)
        if not isinstance(data_data, dict) or data_data.get("code") != "200":
            raise APIError(f"SMS send failed with code {data.get('code')}: {data.get('message')}")

        return self

    def submit_sms_code(self, phone_number: str, sms_code: str) -> str:
        """Complete authentication with SMS code."""
        if not self._lck or not self._auth_methods:
            raise IllegalStateError("Authentication not initiated. Call `open_auth` first.")

        auth_data = {
            "authModuleCode": "userAndSms",
            "authChainCode": self._get_auth_method_by_module_code("userAndSms").auth_chain_code,
            "entityId": self._entity_id,
            "requestType": "chain_type",
            "lck": self._lck,
            "authPara": {"loginName": phone_number, "smsCode": sms_code, "verifyCode": ""},
        }

        rsp = self._session._post(self._SSO_AUTH_EXECUTE, json=auth_data)

        if getattr(rsp, "status_code", 0) != 200:
            raise APIError(f"SMS authentication failed with status code: {getattr(rsp, 'status_code', 'unknown')}")

        data = self._session._dict(rsp)
        # code: int, userName: str, mobile: str, mail: str, message: str, loginToken: str, ...
        # (200 认证成功)
        if data.get("code") != 200:
            raise APIError(f"SMS authentication failed with code {data.get('code')}: {data.get('message', '')}")

        return data["loginToken"]

    def complete_sms_auth(self, token: str) -> _T_RSP:
        """Complete SMS authentication workflow."""
        if not self._lck or not self._auth_methods:
            raise IllegalStateError("Authentication not initiated. Call `open_auth` first.")

        rsp = self._session._post(self._SSO_AUTH_ENGINE, data={"loginToken": token}, redirect=True)

        return self._complete_auth(rsp)
