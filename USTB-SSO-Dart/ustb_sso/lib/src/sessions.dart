library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'exceptions.dart';

/// Simple cookie storage for tracking authentication cookies.
class CookieJar {
  final Map<String, String> _cookies = {};

  /// Parses and stores cookies from Set-Cookie header.
  void setCookiesFromHeader(String? setCookieHeader) {
    if (setCookieHeader == null) return;

    final cookies = setCookieHeader.split(',');
    for (final cookie in cookies) {
      final parts = cookie.trim().split(';');
      if (parts.isNotEmpty) {
        final nameValue = parts[0].split('=');
        if (nameValue.length == 2) {
          final name = nameValue[0].trim();
          final value = nameValue[1].trim();
          _cookies[name] = value;
        }
      }
    }
  }

  /// Parses and stores cookies from response headers.
  void setCookiesFromResponse(http.Response response) {
    // HTTP headers can have multiple Set-Cookie headers
    // The http package combines them into a single string separated by commas
    final setCookieHeaders = response.headers['set-cookie'];
    if (setCookieHeaders != null) {
      setCookiesFromHeader(setCookieHeaders);
    }

    // Also check for individual set-cookie headers in case they're separate
    response.headers.forEach((key, value) {
      if (key.toLowerCase() == 'set-cookie') {
        setCookiesFromHeader(value);
      }
    });
  }

  void clear() => _cookies.clear();

  String? get(String name) => _cookies[name];

  bool has(String name) => _cookies.containsKey(name);

  Map<String, String> get items => Map.unmodifiable(_cookies);

  /// Gets cookie header string for requests.
  String getCookieHeader() {
    if (_cookies.isEmpty) return '';
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }
}

/// Base class for HTTP session management.
abstract class SessionBase {
  late http.Client _client;

  SessionBase(http.Client? client) {
    _client = client ?? _createNewClient();
  }

  /// Performs a GET request.
  Future<http.Response> get(
    String url, {
    bool redirect = false,
    Map<String, String>? headers,
    Map<String, dynamic>? params,
  });

  /// Performs a POST request.
  Future<http.Response> post(
    String url, {
    bool redirect = false,
    Map<String, String>? headers,
    dynamic body,
    Map<String, dynamic>? json,
  });

  /// Converts response to dictionary.
  Map<String, dynamic> responseToDict(http.Response response);

  /// Creates a new client instance.
  http.Client _createNewClient();

  /// Gets the networking client.
  http.Client get client => _client;
}

/// HTTP session implementation using the http package.
class HttpSession extends SessionBase {
  final CookieJar _cookieJar = CookieJar();

  HttpSession([super.client]);

  /// Gets the cookie jar for cookie management.
  CookieJar get cookies => _cookieJar;

  @override
  http.Client _createNewClient() => http.Client();

  @override
  Future<http.Response> get(
    String url, {
    bool redirect = false,
    Map<String, String>? headers,
    Map<String, dynamic>? params,
  }) async {
    final uri = _buildUri(url, params);

    // Use the send method to control redirect behavior
    final request = http.Request('GET', uri);
    request.followRedirects = redirect;

    final Map<String, String> finalHeaders = {...?headers};

    // Add cookies to request
    final cookieHeader = _cookieJar.getCookieHeader();
    if (cookieHeader.isNotEmpty) {
      finalHeaders['Cookie'] = cookieHeader;
    }

    if (finalHeaders.isNotEmpty) {
      request.headers.addAll(finalHeaders);
    }

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    // Store cookies from response
    _cookieJar.setCookiesFromResponse(response);

    return response;
  }

  @override
  Future<http.Response> post(
    String url, {
    bool redirect = false,
    Map<String, String>? headers,
    dynamic body,
    Map<String, dynamic>? json,
  }) async {
    final uri = Uri.parse(url);

    // Use the send method to control redirect behavior
    final request = http.Request('POST', uri);
    request.followRedirects = redirect;

    final Map<String, String> finalHeaders = {...?headers};

    // Add cookies to request
    final cookieHeader = _cookieJar.getCookieHeader();
    if (cookieHeader.isNotEmpty) {
      finalHeaders['Cookie'] = cookieHeader;
    }

    if (json != null) {
      finalHeaders['Content-Type'] = 'application/json';
      request.body = jsonEncode(json);
    } else if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is List<int>) {
        request.bodyBytes = body;
      } else {
        request.body = body.toString();
      }
    }

    request.headers.addAll(finalHeaders);

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    // Store cookies from response
    _cookieJar.setCookiesFromResponse(response);

    return response;
  }

  @override
  Map<String, dynamic> responseToDict(http.Response response) {
    if (response.statusCode != 200) {
      throw APIError('HTTP status code: ${response.statusCode}, expected 200');
    }

    try {
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        throw const BadResponseError('Response is not a JSON object');
      }
      return data;
    } catch (e) {
      throw BadResponseError('Invalid JSON response', cause: e);
    }
  }

  Uri _buildUri(String url, Map<String, dynamic>? params) {
    final uri = Uri.parse(url);
    if (params == null || params.isEmpty) {
      return uri;
    }

    final queryParams = <String, String>{};
    for (final entry in params.entries) {
      queryParams[entry.key] = entry.value.toString();
    }

    return uri.replace(
      queryParameters: {...uri.queryParameters, ...queryParams},
    );
  }
}
