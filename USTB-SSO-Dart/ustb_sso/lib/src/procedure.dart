library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'captcha.dart';
import 'data.dart';
import 'exceptions.dart';
import 'sessions.dart';

/// Base class for authentication procedures.
abstract class AuthProcedureBase {
  static const String ssoAuthEntry =
      'https://sso.ustb.edu.cn/idp/authCenter/authenticate';
  static const String ssoQueryAuthMethods =
      'https://sso.ustb.edu.cn/idp/authn/queryAuthMethods';

  final SessionBase _session;
  final String _entityId;
  final String _redirectUri;
  final String _state;

  String? _lck;
  AuthMethodsResponse? _authMethods;

  AuthProcedureBase({
    required String entityId,
    required String redirectUri,
    String state = 'ustb',
    required SessionBase session,
  }) : _session = session,
       _entityId = entityId,
       _redirectUri = redirectUri,
       _state = state;

  /// Gets the session instance.
  SessionBase get session => _session;

  /// Gets the available authentication methods.
  AuthMethodsResponse get authMethods {
    if (!isOpened) {
      throw const IllegalStateError('Authentication not opened yet.');
    }
    return _authMethods!;
  }

  /// Initiates the authentication workflow. Retrieves the lck and available authentication methods.
  Future<void> openAuth() async {
    await _retrieveAuthEntry();
    await _retrieveAuthMethods();
  }

  /// Checks if the authentication procedure is opened.
  bool get isOpened => _lck != null && _authMethods != null;

  /// Completes authentication workflow with final response processing.
  Future<http.Response> completeAuth(http.Response response) async {
    // Extract text content from response
    final String text = _getResponseText(response);

    // Parse JavaScript variables from response
    final actionTypeMatch = RegExp(
      r'var actionType\s*=\s*"([^"]+)"',
    ).firstMatch(text);
    final locationValueMatch = RegExp(
      r'var locationValue\s*=\s*"([^"]+)"',
    ).firstMatch(text);

    if (actionTypeMatch == null || locationValueMatch == null) {
      throw const BadResponseError('Failed to get authentication destination');
    }

    final actionType = _unescapeString(actionTypeMatch.group(1)!);
    final locationValue = _unescapeString(locationValueMatch.group(1)!);

    if (actionType.toUpperCase() != 'GET') {
      throw UnsupportedMethodError(
        'Unsupported authentication destination method: $actionType',
      );
    }

    return await _session.get(locationValue, redirect: true);
  }

  /// Gets authentication method by module code.
  AuthMethod getAuthMethodByModuleCode(String moduleCode) {
    if (_authMethods == null) {
      throw const IllegalStateError(
        'Authentication methods not queried. Call openAuth first.',
      );
    }
    return _authMethods!.getMethodByModuleCode(moduleCode);
  }

  /// Retrieves authentication entry and extract lck parameter.
  Future<void> _retrieveAuthEntry() async {
    final response = await _session.get(
      ssoAuthEntry,
      params: {
        'client_id': _entityId,
        'redirect_uri': _redirectUri,
        'login_return': 'true',
        'state': _state,
        'response_type': 'code',
      },
      redirect: false,
    );

    final statusCode = _getStatusCode(response);
    if (statusCode < 300 || statusCode >= 400) {
      throw APIError('HTTP status code: $statusCode, expected 3xx');
    }

    final headers = _getHeaders(response);
    final location = headers['location'];
    if (location == null) {
      throw const BadResponseError('Missing "Location" header in response');
    }

    final uri = Uri.parse(location.replaceAll('/#/', '/'));
    _lck = uri.queryParameters['lck'];
    if (_lck == null) {
      throw const BadResponseError(
        'Failed to extract "lck" from Location header',
      );
    }
  }

  /// Retrieves available authentication methods.
  Future<void> _retrieveAuthMethods() async {
    if (_lck == null) {
      throw const IllegalStateError('Authentication not opened yet.');
    }

    final response = await _session.post(
      ssoQueryAuthMethods,
      json: {'lck': _lck, 'entityId': _entityId},
    );

    final statusCode = _getStatusCode(response);
    if (statusCode != 200) {
      throw APIError('Query auth methods failed with status code: $statusCode');
    }

    final data = _session.responseToDict(response);
    if (data['code'] != 200) {
      throw APIError(
        'Query auth methods failed with code ${data['code']}: ${data['message'] ?? ''}',
      );
    }

    _authMethods = AuthMethodsResponse.fromJson(data);
  }

  // Abstract methods to be implemented by subclasses

  String _getResponseText(http.Response response);
  int _getStatusCode(http.Response response);
  Map<String, String> _getHeaders(http.Response response);

  /// Utility method to unescape HTML entities and URL encoding.
  String _unescapeString(String input) {
    return Uri.decodeComponent(
      input.replaceAll('&quot;', '"').replaceAll('&amp;', '&'),
    );
  }
}

/// Authentication procedure implementation for HTTP responses.
abstract class HttpAuthProcedureBase extends AuthProcedureBase {
  HttpAuthProcedureBase({
    required super.entityId,
    required super.redirectUri,
    super.state,
    required super.session,
  });

  @override
  String _getResponseText(http.Response response) => response.body;

  @override
  int _getStatusCode(http.Response response) => response.statusCode;

  @override
  Map<String, String> _getHeaders(http.Response response) => response.headers;
}

/// QR code authentication procedure implementation.
class QrAuthProcedure extends HttpAuthProcedureBase {
  static const String ssoQrInfo =
      'https://sso.ustb.edu.cn/idp/authn/getMicroQr';
  static const String sisQrPage = 'https://sis.ustb.edu.cn/connect/qrpage';
  static const String sisQrImg = 'https://sis.ustb.edu.cn/connect/qrimg';
  static const String sisQrState = 'https://sis.ustb.edu.cn/connect/state';
  static const int qrCodeTimeout = 180;
  static const int pollingTimeout = 16;

  String? _appId;
  String? _returnUrl;
  String? _randomToken;
  String? _sid;

  QrAuthProcedure({
    required super.entityId,
    required super.redirectUri,
    super.state,
    required super.session,
  });

  /// Prepares WeChat authentication info.
  Future<QrAuthProcedure> useWechatAuth() async {
    if (_lck == null) {
      throw const IllegalStateError(
        'Authentication not initiated. Call openAuth first.',
      );
    }

    final response = await _session.post(
      ssoQrInfo,
      json: {'entityId': _entityId, 'lck': _lck},
    );

    final data = _session.responseToDict(response);
    if (data['code'] != '200') {
      throw APIError('API code ${data['code']}: ${data['message'] ?? ''}');
    }

    try {
      final responseData = data['data'] as Map<String, dynamic>;
      _appId = responseData['appId'] as String;
      _returnUrl = responseData['returnUrl'] as String;
      _randomToken = responseData['randomToken'] as String;
    } catch (e) {
      throw BadResponseError('Missing key in response', cause: e);
    }

    return this;
  }

  /// Prepares QR code SID from QR page.
  Future<QrAuthProcedure> useQrCode() async {
    if (_appId == null || _returnUrl == null || _randomToken == null) {
      throw const IllegalStateError(
        'Not in WeChat mode yet. Call useWechatAuth first.',
      );
    }

    final response = await _session.get(
      sisQrPage,
      params: {
        'appid': _appId!,
        'return_url': _returnUrl!,
        'rand_token': _randomToken!,
        'embed_flag': '1',
      },
    );

    if (_getStatusCode(response) != 200) {
      throw APIError(
        'HTTP status code ${_getStatusCode(response)}, expected 200',
      );
    }

    final text = _getResponseText(response);
    final match = RegExp(r'sid\s?=\s?(\w{32})').firstMatch(text);
    if (match == null) {
      throw const BadResponseError('SID not found in QR page');
    }
    _sid = match.group(1);

    return this;
  }

  /// Downloads QR code image and returns it in bytes.
  Future<Uint8List> getQrImage() async {
    if (_sid == null) {
      throw const IllegalStateError('SID not available. Call useQrCode first.');
    }

    final response = await _session.get(sisQrImg, params: {'sid': _sid!});

    if (_getStatusCode(response) != 200) {
      throw APIError(
        'QR image request failed with HTTP status code ${_getStatusCode(response)}',
      );
    }

    return response.bodyBytes;
  }

  /// Polls the authentication status until completion or timeout.
  /// Returns the pass code if completed. Throws exception when timed out.
  Future<String> waitForPassCode() async {
    if (_sid == null) {
      throw const IllegalStateError('SID not available. Call useQrCode first.');
    }

    final startTime = DateTime.now();
    while (DateTime.now().difference(startTime).inSeconds < qrCodeTimeout) {
      try {
        final response = await _session.get(sisQrState, params: {'sid': _sid!});
        final data = _session.responseToDict(response);

        final code = data['code'] as int?;
        if (code == 1) {
          // Success
          return data['data'] as String;
        } else if (code == 3 || code == 202) {
          // Expired
          throw const TimeoutError('QR code expired');
        } else if (code == 4) {
          // Timeout, continue polling
          await Future.delayed(const Duration(seconds: 1));
          continue;
        } else if (code == 101 || code == 102) {
          // Invalid
          throw APIError('API code $code: ${data['message'] ?? ''}');
        }
      } catch (e) {
        if (e is TimeoutError || e is APIError) {
          rethrow;
        }
        // Network error, continue polling
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }
    }

    throw const TimeoutError('Authentication polling timed out');
  }

  /// Completes authentication workflow.
  Future<http.Response> completeQrAuth(String passCode) async {
    if (_appId == null || _returnUrl == null || _randomToken == null) {
      throw const IllegalStateError('Authentication not well established');
    }

    final params = <String, String>{
      'appid': _appId!,
      'auth_code': passCode,
      'rand_token': _randomToken!,
    };

    // Safe handling of return_url parsing
    if (_returnUrl != null) {
      final uri = Uri.parse(_returnUrl!);
      for (final entry in uri.queryParameters.entries) {
        params[entry.key] = entry.value;
      }
    }

    final response = await _session.get(
      _returnUrl!,
      params: params,
      redirect: true,
    );
    return await completeAuth(response);
  }
}

/// SMS authentication procedure implementation.
class SmsAuthProcedure extends HttpAuthProcedureBase {
  static const String ssoCaptchaCheck =
      'https://sso.ustb.edu.cn/idp/captcha/checkOpen';
  static const String ssoCaptchaPuzzle =
      'https://sso.ustb.edu.cn/idp/captcha/getBlockPuzzle';
  static const String ssoSmsSend =
      'https://sso.ustb.edu.cn/idp/authn/sendSmsMsg';
  static const String ssoAuthExecute =
      'https://sso.ustb.edu.cn/idp/authn/authExecute';
  static const String ssoAuthEngine =
      'https://sso.ustb.edu.cn/idp/authCenter/authnEngine?locale=zh-CN';

  SmsAuthProcedure({
    required super.entityId,
    required super.redirectUri,
    super.state,
    required super.session,
  });

  /// Check if SMS authentication is available.
  Future<SmsAuthProcedure> checkSmsAvailable() async {
    if (_authMethods == null) {
      throw const IllegalStateError(
        'Authentication methods not queried. Call openAuth first.',
      );
    }

    // Check if SMS authentication method is available
    try {
      getAuthMethodByModuleCode('userAndSms');
    } catch (e) {
      throw const APIError(
        'SMS authentication method is not available for this entity',
      );
    }

    // Additional check via the captcha endpoint
    final response = await _session.get(
      ssoCaptchaCheck,
      params: {'type': 'sms'},
    );

    if (_getStatusCode(response) != 200) {
      throw APIError(
        'SMS check failed with status code: ${_getStatusCode(response)}',
      );
    }

    return this;
  }

  /// Gets captcha puzzle.
  Future<CaptchaData> _getCaptcha() async {
    final response = await _session.get(ssoCaptchaPuzzle);

    if (_getStatusCode(response) != 200) {
      throw APIError(
        'Captcha puzzle request failed with status code: ${_getStatusCode(response)}',
      );
    }

    final data = _session.responseToDict(response);

    try {
      final captchaData = data['data'] as Map<String, dynamic>;
      final originalImage = captchaData['originalImageBase64'] as String;
      final jigsawImage = captchaData['jigsawImageBase64'] as String;
      final token = captchaData['token'] as String;

      return CaptchaData(
        originalImageBase64: originalImage,
        jigsawImageBase64: jigsawImage,
        token: token,
      );
    } catch (e) {
      throw BadResponseError('Missing captcha data in response', cause: e);
    }
  }

  int _solveCaptcha(String originalImageBase64, String jigsawImageBase64) {
    try {
      // Initialize the puzzle captcha solver
      final solver = PuzzleCaptchaSolver();

      // Decode background image from base64
      final backgroundBytes = base64Decode(originalImageBase64);
      final puzzleBytes = base64Decode(jigsawImageBase64);

      // Solve captcha using the native Dart implementation
      final result = solver.handleBytes(
        Uint8List.fromList(backgroundBytes),
        Uint8List.fromList(puzzleBytes),
      );

      return result.x;
    } catch (e) {
      print('Captcha solving failed: $e');
      return 100;
    }
  }

  /// Sends SMS verification code.
  Future<SmsAuthProcedure> sendSms(String phoneNumber) async {
    if (_lck == null) {
      throw const IllegalStateError(
        'Authentication not initiated. Call openAuth first.',
      );
    }

    final captchaData = await _getCaptcha();
    final x = _solveCaptcha(
      captchaData.originalImageBase64,
      captchaData.jigsawImageBase64,
    );

    // Prepare SMS request data
    final smsData = {
      'loginName': phoneNumber,
      'pointJson': jsonEncode({'x': x - 5, 'y': 5}),
      'token': captchaData.token,
      'lck': _lck,
    };

    final response = await _session.post(ssoSmsSend, json: smsData);

    if (_getStatusCode(response) != 200) {
      throw APIError(
        'SMS send request failed with status code: ${_getStatusCode(response)}',
      );
    }

    final data = _session.responseToDict(response);
    final dataData = data['data'] as Map<String, dynamic>?;

    if (dataData == null || dataData['code'] != '200') {
      throw APIError(
        'SMS send failed with code ${data['code']}: ${data['message']}',
      );
    }

    return this;
  }

  /// Complete authentication with SMS code.
  Future<String> submitSmsCode(String phoneNumber, String smsCode) async {
    if (_lck == null || _authMethods == null) {
      throw const IllegalStateError(
        'Authentication not initiated. Call openAuth first.',
      );
    }

    final authData = {
      'authModuleCode': 'userAndSms',
      'authChainCode': getAuthMethodByModuleCode('userAndSms').authChainCode,
      'entityId': _entityId,
      'requestType': 'chain_type',
      'lck': _lck,
      'authPara': {
        'loginName': phoneNumber,
        'smsCode': smsCode,
        'verifyCode': '',
      },
    };

    final response = await _session.post(ssoAuthExecute, json: authData);

    if (_getStatusCode(response) != 200) {
      throw APIError(
        'SMS authentication failed with status code: ${_getStatusCode(response)}',
      );
    }

    final data = _session.responseToDict(response);
    if (data['code'] != 200) {
      throw APIError(
        'SMS authentication failed with code ${data['code']}: ${data['message'] ?? ''}',
      );
    }

    return data['loginToken'] as String;
  }

  /// Completes SMS authentication workflow.
  Future<http.Response> completeSmsAuth(String token) async {
    if (_lck == null || _authMethods == null) {
      throw const IllegalStateError(
        'Authentication not initiated. Call openAuth first.',
      );
    }

    final response = await _session.post(
      ssoAuthEngine,
      body: 'loginToken=$token',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      redirect: true,
    );

    return await completeAuth(response);
  }
}

/// Captcha data container.
class CaptchaData {
  final String originalImageBase64;
  final String jigsawImageBase64;
  final String token;

  const CaptchaData({
    required this.originalImageBase64,
    required this.jigsawImageBase64,
    required this.token,
  });
}
