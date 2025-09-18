import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:ustb_sso/src/captcha.dart';

void main() {
  group('Captcha Test', () {
    test('Solve Test Images', () async {
      const puzzleUrl = 'https://ghproxy.net/https://raw.githubusercontent.com/isHarryh/No-Puzzle-Captcha/main/tests/tricky_test/IMG_000_P.png';
      const backgroundUrl = 'https://ghproxy.net/https://raw.githubusercontent.com/isHarryh/No-Puzzle-Captcha/main/tests/tricky_test/IMG_000_O.png';
      const expectedX = 177;
      const expectedY = 0;
      const tolerance = 5;

      try {
        print('Downloading test images...');
        final results = await Future.wait([
          http.get(Uri.parse(puzzleUrl)),
          http.get(Uri.parse(backgroundUrl)),
        ]);

        final puzzleResponse = results[0];
        final backgroundResponse = results[1];

        expect(puzzleResponse.statusCode, equals(200), reason: 'Failed to download puzzle image');
        expect(backgroundResponse.statusCode, equals(200), reason: 'Failed to download background image');

        final puzzleBytes = puzzleResponse.bodyBytes;
        final backgroundBytes = backgroundResponse.bodyBytes;

        final puzzleMatrix = ImageMatrix.fromBytes(puzzleBytes);
        final backgroundMatrix = ImageMatrix.fromBytes(backgroundBytes);

        print('  Puzzle size: ${puzzleMatrix.width}x${puzzleMatrix.height}');
        print('  Background size: ${backgroundMatrix.width}x${backgroundMatrix.height}');

        print('Testing captcha solver...');
        final solver = PuzzleCaptchaSolver();
        final result = solver.handleImage(backgroundMatrix, puzzleMatrix);

        print('  Result: x=${result.x}, y=${result.y}, elapsed=${(result.elapsedTime * 1000).round()}ms');
        print('  Expected: x=$expectedX±$tolerance, y=$expectedY±$tolerance');

        expect(result.x, greaterThanOrEqualTo(0), reason: 'X coordinate should be non-negative');
        expect(result.y, greaterThanOrEqualTo(0), reason: 'Y coordinate should be non-negative');
        expect(result.elapsedTime, greaterThan(0.0), reason: 'Elapsed time should be positive');

        final xDiff = (result.x - expectedX).abs();
        final yDiff = (result.y - expectedY).abs();

        expect(xDiff, lessThanOrEqualTo(tolerance),
               reason: 'X coordinate ${result.x} should be within $tolerance pixels of expected $expectedX');
        expect(yDiff, lessThanOrEqualTo(tolerance),
               reason: 'Y coordinate ${result.y} should be within $tolerance pixels of expected $expectedY');

        print('Test OKAY!');

      } catch (e, stackTrace) {
        print('Test FAILED: $e');
        print('Stack trace: $stackTrace');
        rethrow;
      }
    });
  });
}
