library;

/// Base exception for authentication errors.
abstract class AuthException implements Exception {
  final String message;
  final dynamic cause;

  const AuthException(this.message, {this.cause});

  @override
  String toString() {
    if (cause != null) {
      return 'AuthException: $message (cause: $cause)';
    }
    return 'AuthException: $message';
  }
}

/// Exception raised for unexpected HTTP status code or API status code.
class APIError extends AuthException {
  const APIError(super.message, {super.cause});

  @override
  String toString() => 'APIError: $message';
}

/// Exception raised for unparsable API response.
class BadResponseError extends AuthException {
  const BadResponseError(super.message, {super.cause});

  @override
  String toString() => 'BadResponseError: $message';
}

/// Exception raised when authentication gets into illegal state.
class IllegalStateError extends AuthException {
  const IllegalStateError(super.message, {super.cause});

  @override
  String toString() => 'IllegalStateError: $message';
}

/// Exception raised when authentication times out or expired.
class TimeoutError extends AuthException {
  const TimeoutError(super.message, {super.cause});

  @override
  String toString() => 'TimeoutError: $message';
}

/// Exception raised when an unsupported authentication method is given.
class UnsupportedMethodError extends AuthException {
  const UnsupportedMethodError(super.message, {super.cause});

  @override
  String toString() => 'UnsupportedMethodError: $message';
}
