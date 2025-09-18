import 'package:ustb_sso/ustb_sso.dart';
import 'package:test/test.dart';

void main() {
  group('Server Test', () {
    test('Get Auth Methods', () async {
      // Test JWGL platform
      await _testPlatformAuthMethods(
        'JWGL',
        Prefabs.jwglUstbEduCn,
      );

      // Test CHAT platform
      await _testPlatformAuthMethods(
        'CHAT',
        Prefabs.chatUstbEduCn,
      );
    });
  });
}

Future<void> _testPlatformAuthMethods(String platformName, ApplicationParam config) async {
  print('Testing auth methods for $platformName platform...');

  try {
    final session = HttpSession();
    final auth = QrAuthProcedure(
      entityId: config.entityId,
      redirectUri: config.redirectUri,
      state: config.state,
      session: session,
    );

    await auth.openAuth();

    final authMethods = auth.authMethods;

    expect(authMethods.data.length, greaterThan(0),
           reason: '$platformName should have at least one authentication method');

    print('$platformName platform has ${authMethods.data.length} auth method(s):');
    for (final method in authMethods.data) {
      print('  - ${method.chainName} (${method.moduleCode})');
    }

  } catch (e) {
    fail('Failed to get auth methods for $platformName: $e');
  }
}
