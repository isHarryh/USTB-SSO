class AuthException(Exception):
    """Base exception for authentication errors.
    """


class APIError(AuthException):
    """Exception raised for unexpected HTTP status code or API status code.
    """


class BadResponseError(AuthException):
    """Exception raised for unparsable API response.
    """


class IllegalStateError(AuthException):
    """Exception raised when authentication gets into illegal state.
    """


class TimeoutError(AuthException):
    """Exception raised when authentication times out or expired.
    """


class UnsupportedMethodError(AuthException):
    """Exception raised when an unsupported authentication method is given.
    """
