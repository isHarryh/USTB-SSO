import 'dart:io';
import 'package:ustb_sso/ustb_sso.dart';
import 'package:http/http.dart' as http;

extension IterableExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Test platform configuration.
class TestPlatform {
  final String name;
  final ApplicationParam config;
  final bool Function(HttpSession session, http.Response response)
  validationFunc;

  TestPlatform({
    required this.name,
    required this.config,
    required this.validationFunc,
  });
}

/// Test method configuration.
class TestMethod {
  final String name;
  final Future<http.Response> Function(dynamic auth, TestPlatform platform)
  testFunc;

  TestMethod({required this.name, required this.testFunc});
}

void main() async {
  print('USTB SSO Authentication Test Suite');
  print('=' * 50);

  // Define available platforms
  final platforms = {
    'JWGL': TestPlatform(
      name: 'JWGL',
      config: Prefabs.jwglUstbEduCn,
      validationFunc: validateJwglResponse,
    ),
    'CHAT': TestPlatform(
      name: 'CHAT',
      config: Prefabs.chatUstbEduCn,
      validationFunc: validateChatResponse,
    ),
    'BYYT': TestPlatform(
      name: 'BYYT',
      config: Prefabs.byytUstbEduCn,
      validationFunc: validateByytResponse,
    ),
  };

  // Define available methods
  final methods = {
    'QR': TestMethod(name: 'QR', testFunc: testQrAuth),
    'SMS': TestMethod(name: 'SMS', testFunc: testSmsAuth),
  };

  // Generate test combinations as ordered pairs
  final testCombinations = <MapEntry<String, String>>[];
  for (final platformKey in platforms.keys.toList()..sort()) {
    for (final methodKey in methods.keys.toList()..sort()) {
      testCombinations.add(MapEntry(platformKey, methodKey));
    }
  }

  // Run basic tests first
  await testAuthMethodsQuery();

  // Interactive test selection
  while (true) {
    print('=' * 50);
    print('Available test combinations (Platform, Method):');
    for (int i = 0; i < testCombinations.length; i++) {
      final combination = testCombinations[i];
      final platform = platforms[combination.key]!;
      final method = methods[combination.value]!;
      print(
        '${i + 1}. (${combination.key}, ${combination.value}) - ${platform.name} + ${method.name} Authentication',
      );
    }

    print('${testCombinations.length + 1}. Run all tests');
    print('${testCombinations.length + 2}. Exit');
    print('=' * 50);

    try {
      stdout.write('Select test to run (1-${testCombinations.length + 2}): ');
      final input = stdin.readLineSync();
      if (input == null) break;

      final choice = int.parse(input.trim());

      if (choice >= 1 && choice <= testCombinations.length) {
        final combination = testCombinations[choice - 1];
        final platform = platforms[combination.key]!;
        final method = methods[combination.value]!;
        await runTest(platform, method);
      } else if (choice == testCombinations.length + 1) {
        print('\n🚀 Running all test combinations...');
        for (final combination in testCombinations) {
          final platform = platforms[combination.key]!;
          final method = methods[combination.value]!;
          await runTest(platform, method);
        }
      } else if (choice == testCombinations.length + 2) {
        print('\n🚫 Exiting test suite.');
        break;
      } else {
        print(
          'Invalid choice. Please select 1-${testCombinations.length + 2}.',
        );
      }
    } catch (e) {
      if (e is FormatException) {
        print('Invalid input. Please enter a number.');
      } else {
        print('Error: $e');
      }
    }
  }
}

/// Validation function for JWGL response.
bool validateJwglResponse(HttpSession session, http.Response response) {
  // Check if we reached the framework page
  final hasFrameworkUrl =
      response.request?.url.toString().contains(
        '//jwgl.ustb.edu.cn/framework',
      ) ??
      false;

  // Check for JSESSIONID cookie (main authentication cookie for JWGL)
  final hasJSessionId = session.cookies.has('JSESSIONID');

  if (hasJSessionId) {
    final jsessionId = session.cookies.get('JSESSIONID');
    print('JWGL: Authentication cookie found - JSESSIONID = $jsessionId');
  }

  return hasFrameworkUrl && hasJSessionId;
}

/// Validation function for CHAT response.
bool validateChatResponse(HttpSession session, http.Response response) {
  // Check if we have the expected cookie_vjuid_login
  final hasChatCookie = session.cookies.has('cookie_vjuid_login');

  if (hasChatCookie) {
    final chatCookie = session.cookies.get('cookie_vjuid_login');
    print(
      'CHAT: Authentication cookie found - cookie_vjuid_login = $chatCookie',
    );
  }

  // Check if we have the expected response or cookie
  final hasValidResponse =
      response.statusCode == 200 ||
      response.request?.url.toString().contains('chat.ustb.edu.cn') == true;

  return hasValidResponse && hasChatCookie;
}

bool validateByytResponse(HttpSession session, http.Response response) {
  // Check if we have the expected cookie (e.g., auth_token or similar)
  final hasByytCookie =
      session.cookies.has('INCO') && session.cookies.has('SESSION');

  if (hasByytCookie) {
    final byytIncoCookie = session.cookies.get('INCO');
    print('BYYT: Authentication cookie found - INCO = $byytIncoCookie');
    final byytSessionCookie = session.cookies.get('SESSION');
    print('BYYT: Authentication cookie found - SESSION = $byytSessionCookie');
  }

  // Check if we have the expected response or cookie
  final hasValidResponse =
      response.statusCode == 200 ||
      response.request?.url.toString().contains('byyt.ustb.edu.cn') == true;

  return hasValidResponse && hasByytCookie;
}

/// Tests authentication methods query.
Future<void> testAuthMethodsQuery() async {
  print('Testing Authentication Methods Query');
  print('=' * 50);

  final session = HttpSession();
  final auth = QrAuthProcedure(
    entityId: Prefabs.jwglUstbEduCn.entityId,
    redirectUri: Prefabs.jwglUstbEduCn.redirectUri,
    state: Prefabs.jwglUstbEduCn.state,
    session: session,
  );

  try {
    print('Starting authentication methods query test');
    await auth.openAuth();

    final authMethods = auth.authMethods;
    print('\nDetailed authentication methods information:');
    for (final method in authMethods.data) {
      print('  Chain: ${method.chainName}');
      print('  Module: ${method.moduleName} (${method.moduleCode})');
      print('');
    }

    final smsMethod = authMethods.data
        .where((m) => m.moduleCode == 'userAndSms')
        .firstOrNull;
    final qrMethod = authMethods.data
        .where((m) => m.moduleCode == 'microQr')
        .firstOrNull;

    print('Method availability check:');
    print('  - SMS method: ${smsMethod != null ? 'Available' : 'Not found'}');
    print('  - QR method: ${qrMethod != null ? 'Available' : 'Not found'}');

    print('Authentication methods query: ✅ PASSED');
  } catch (e) {
    print('Authentication methods query: ❌ FAILED: $e');
    print('📄 Stack trace:');
    print(e);
  }
}

/// Runs a specific platform-method test combination.
Future<void> runTest(TestPlatform platform, TestMethod method) async {
  print('Testing ${platform.name} with ${method.name} authentication');
  print('=' * 50);

  try {
    final session = HttpSession();
    dynamic auth;

    if (method.name == 'QR') {
      auth = QrAuthProcedure(
        entityId: platform.config.entityId,
        redirectUri: platform.config.redirectUri,
        state: platform.config.state,
        session: session,
      );
    } else if (method.name == 'SMS') {
      auth = SmsAuthProcedure(
        entityId: platform.config.entityId,
        redirectUri: platform.config.redirectUri,
        state: platform.config.state,
        session: session,
      );
    } else {
      throw UnsupportedError('Unknown method: ${method.name}');
    }

    // Start authentication
    print('${platform.name}: Starting authentication');
    await auth.openAuth();

    // Display available methods for debugging
    print('\n${platform.name}: Available authentication methods:');
    for (final m in auth.authMethods.data) {
      print('  - ${m.chainName} (${m.moduleCode})');
    }
    print('');

    // Run the specific test method
    final response = await method.testFunc(auth, platform);

    // Validate response
    if (platform.validationFunc(session, response)) {
      print('${platform.name}: ✅ Test PASSED - Authentication successful');
    } else {
      print('${platform.name}: ❌ Test FAILED - Authentication failed');
    }
  } catch (e) {
    print('${platform.name}: ❌ Test FAILED - Exception: $e');
    print('${platform.name}: 📄 Stack trace:');
    print(e);
  }
}

/// Tests QR authentication.
Future<http.Response> testQrAuth(
  dynamic authProcedure,
  TestPlatform platform,
) async {
  final auth = authProcedure as QrAuthProcedure;

  print('${platform.name}: Setting up QR authentication');

  await auth.useWechatAuth();
  await auth.useQrCode();

  final qrPath = 'qr.png';
  final qrImageBytes = await auth.getQrImage();
  final qrFile = File(qrPath);
  await qrFile.writeAsBytes(qrImageBytes);

  print('${platform.name}: QR code saved to $qrPath');
  print('${platform.name}: Please scan the QR code to continue');

  try {
    final passCode = await auth.waitForPassCode();
    print('${platform.name}: QR code scanned, completing authentication');
    return await auth.completeQrAuth(passCode);
  } catch (e) {
    print('${platform.name}: QR authentication timeout or error: $e');
    // Return a mock response for timeout
    return http.Response('{"error": "timeout"}', 408);
  }
}

/// Tests SMS authentication.
Future<http.Response> testSmsAuth(
  dynamic authProcedure,
  TestPlatform platform,
) async {
  final auth = authProcedure as SmsAuthProcedure;

  print('${platform.name}: Setting up SMS authentication');

  try {
    await auth.checkSmsAvailable();
    print('${platform.name}: SMS authentication is available');
  } catch (e) {
    print('${platform.name}: SMS authentication not available: $e');
    rethrow;
  }

  stdout.write(
    'Enter phone number for ${platform.name} SMS auth (or "skip" to skip): ',
  );
  final phoneNumber = stdin.readLineSync();

  if (phoneNumber?.toLowerCase() == 'skip' || phoneNumber?.isEmpty == true) {
    print('${platform.name}: SMS test skipped by user');
    return http.Response('{"status": "skipped"}', 200);
  }

  print('${platform.name}: Sending SMS to $phoneNumber');
  await auth.sendSms(phoneNumber!);

  stdout.write('Enter SMS verification code for ${platform.name}: ');
  final smsCode = stdin.readLineSync();

  if (smsCode?.isEmpty == true) {
    print('${platform.name}: SMS test cancelled - no code provided');
    return http.Response('{"error": "cancelled"}', 400);
  }

  print('${platform.name}: Received SMS code $smsCode, verifying');
  final token = await auth.submitSmsCode(phoneNumber, smsCode!);

  print('${platform.name}: SMS Verified, completing SMS authentication');
  return await auth.completeSmsAuth(token);
}
