library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Represents an image as a 2D matrix of pixel values.
class ImageMatrix {
  final List<List<int>> data;
  final int height;
  final int width;
  final int channels;

  ImageMatrix(this.data, this.height, this.width, this.channels);

  /// Creates a gray scale image matrix from pixel data.
  factory ImageMatrix.grayScale(List<List<int>> data) {
    return ImageMatrix(data, data.length, data[0].length, 1);
  }

  /// Creates an RGB image matrix from pixel data.
  factory ImageMatrix.rgb(List<List<List<int>>> data) {
    final height = data.length;
    final width = data[0].length;
    final flattened = <List<int>>[];

    for (int y = 0; y < height; y++) {
      final row = <int>[];
      for (int x = 0; x < width; x++) {
        final r = data[y][x][0];
        final g = data[y][x][1];
        final b = data[y][x][2];
        final gray = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
        row.add(gray);
      }
      flattened.add(row);
    }

    return ImageMatrix(flattened, height, width, 1);
  }

  /// Creates from image bytes.
  factory ImageMatrix.fromBytes(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw ArgumentError('Failed to decode image from ${bytes.length} bytes');
    }

    // Convert to gray scale matrix
    final data = <List<int>>[];
    for (int y = 0; y < image.height; y++) {
      final row = <int>[];
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final gray = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
        row.add(gray);
      }
      data.add(row);
    }

    return ImageMatrix(data, image.height, image.width, 1);
  }

  /// Gets pixel value at coordinates.
  int getPixel(int x, int y) {
    if (y >= 0 && y < height && x >= 0 && x < width) {
      return data[y][x];
    }
    return 0;
  }

  /// Sets pixel value at coordinates.
  void setPixel(int x, int y, int value) {
    if (y >= 0 && y < height && x >= 0 && x < width) {
      data[y][x] = value;
    }
  }

  /// Creates a copy of this image matrix.
  ImageMatrix copy() {
    final newData = <List<int>>[];
    for (final row in data) {
      newData.add(List<int>.from(row));
    }
    return ImageMatrix(newData, height, width, channels);
  }
}

/// Base class for image transformations.
abstract class ImageTransform {
  /// Transforms the input image and return the processed image.
  ImageMatrix transform(ImageMatrix image);
}

/// Returns the input image unchanged.
class RawTransform extends ImageTransform {
  @override
  ImageMatrix transform(ImageMatrix image) {
    return image.copy();
  }
}

/// Applies min-max normalization to an image.
class NormalizeTransform extends ImageTransform {
  @override
  ImageMatrix transform(ImageMatrix image) {
    final result = image.copy();

    // Find min and max values
    int minVal = 255;
    int maxVal = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        minVal = math.min(minVal, pixel);
        maxVal = math.max(maxVal, pixel);
      }
    }

    // Normalize to 0-255 range
    final range = maxVal - minVal;
    if (range == 0) {
      return result; // Avoid division by zero
    }

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final normalized = ((pixel - minVal) * 255.0 / range).round();
        result.setPixel(x, y, normalized);
      }
    }

    return result;
  }
}

/// Applies Canny edge detection to an image.
class EdgeTransform extends ImageTransform {
  final int lowThreshold;
  final int highThreshold;

  EdgeTransform(this.lowThreshold, this.highThreshold);

  @override
  ImageMatrix transform(ImageMatrix image) {
    final blurred = _applyGaussianBlur(image);
    final gradients = _calculateGradients(blurred);
    final suppressed = _nonMaximumSuppression(gradients);
    final edges = _doubleThreshold(suppressed);
    return edges;
  }

  /// Applies a simple Gaussian blur.
  ImageMatrix _applyGaussianBlur(ImageMatrix image) {
    final kernel = [
      [1, 4, 6, 4, 1],
      [4, 16, 24, 16, 4],
      [6, 24, 36, 24, 6],
      [4, 16, 24, 16, 4],
      [1, 4, 6, 4, 1],
    ];

    final result = image.copy();
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        int sum = 0;
        int weightSum = 0;

        for (int ky = -2; ky <= 2; ky++) {
          for (int kx = -2; kx <= 2; kx++) {
            final py = y + ky;
            final px = x + kx;

            final clampedY = py.clamp(0, image.height - 1);
            final clampedX = px.clamp(0, image.width - 1);

            final weight = kernel[ky + 2][kx + 2];
            sum += image.getPixel(clampedX, clampedY) * weight;
            weightSum += weight;
          }
        }

        result.setPixel(x, y, (sum / weightSum).round().clamp(0, 255));
      }
    }

    return result;
  }

  /// Calculates gradients using Sobel operators.
  _GradientData _calculateGradients(ImageMatrix image) {
    final magnitude = ImageMatrix(
      List.generate(image.height, (_) => List.filled(image.width, 0)),
      image.height,
      image.width,
      1,
    );
    final direction = List.generate(
      image.height,
      (_) => List.filled(image.width, 0.0),
    );

    final sobelX = [
      [-1, 0, 1],
      [-2, 0, 2],
      [-1, 0, 1],
    ];
    final sobelY = [
      [-1, -2, -1],
      [0, 0, 0],
      [1, 2, 1],
    ];

    for (int y = 1; y < image.height - 1; y++) {
      for (int x = 1; x < image.width - 1; x++) {
        int gx = 0, gy = 0;

        for (int ky = -1; ky <= 1; ky++) {
          for (int kx = -1; kx <= 1; kx++) {
            final pixel = image.getPixel(x + kx, y + ky);
            gx += pixel * sobelX[ky + 1][kx + 1];
            gy += pixel * sobelY[ky + 1][kx + 1];
          }
        }

        final mag = math.sqrt(gx * gx + gy * gy);
        magnitude.setPixel(x, y, mag.round());
        direction[y][x] = math.atan2(gy, gx);
      }
    }

    return _GradientData(magnitude, direction);
  }

  /// Applies non-maximum suppression.
  ImageMatrix _nonMaximumSuppression(_GradientData gradients) {
    final result = gradients.magnitude.copy();

    for (int y = 1; y < gradients.magnitude.height - 1; y++) {
      for (int x = 1; x < gradients.magnitude.width - 1; x++) {
        final angle = gradients.direction[y][x];
        final mag = gradients.magnitude.getPixel(x, y);

        double normalizedAngle = angle * 180 / math.pi;
        if (normalizedAngle < 0) normalizedAngle += 180;

        int neighbor1 = 0, neighbor2 = 0;

        if ((normalizedAngle >= 0 && normalizedAngle < 22.5) ||
            (normalizedAngle >= 157.5 && normalizedAngle <= 180)) {
          // 0 deg
          neighbor1 = gradients.magnitude.getPixel(x - 1, y);
          neighbor2 = gradients.magnitude.getPixel(x + 1, y);
        } else if (normalizedAngle >= 22.5 && normalizedAngle < 67.5) {
          // 45 deg
          neighbor1 = gradients.magnitude.getPixel(x + 1, y - 1);
          neighbor2 = gradients.magnitude.getPixel(x - 1, y + 1);
        } else if (normalizedAngle >= 67.5 && normalizedAngle < 112.5) {
          // 90 deg
          neighbor1 = gradients.magnitude.getPixel(x, y - 1);
          neighbor2 = gradients.magnitude.getPixel(x, y + 1);
        } else {
          // 135 deg
          neighbor1 = gradients.magnitude.getPixel(x - 1, y - 1);
          neighbor2 = gradients.magnitude.getPixel(x + 1, y + 1);
        }

        if (mag < neighbor1 || mag < neighbor2) {
          result.setPixel(x, y, 0);
        }
      }
    }

    return result;
  }

  /// Applies double threshold to create strong and weak edges.
  ImageMatrix _doubleThreshold(ImageMatrix image) {
    final result = ImageMatrix(
      List.generate(image.height, (_) => List.filled(image.width, 0)),
      image.height,
      image.width,
      1,
    );

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);

        if (pixel >= highThreshold) {
          result.setPixel(x, y, 255); // Strong edge
        } else if (pixel >= lowThreshold) {
          result.setPixel(x, y, 128); // Weak edge
        } else {
          result.setPixel(x, y, 0); // Not an edge
        }
      }
    }

    // Edge tracking by hysteresis using iterative approach (more accurate)
    bool changed = true;
    while (changed) {
      changed = false;
      for (int y = 1; y < image.height - 1; y++) {
        for (int x = 1; x < image.width - 1; x++) {
          if (result.getPixel(x, y) == 128) {
            // Check if connected to strong edge
            bool connectedToStrong = false;
            for (int dy = -1; dy <= 1; dy++) {
              for (int dx = -1; dx <= 1; dx++) {
                if (dx == 0 && dy == 0) continue;
                if (result.getPixel(x + dx, y + dy) == 255) {
                  connectedToStrong = true;
                  break;
                }
              }
              if (connectedToStrong) break;
            }

            if (connectedToStrong) {
              result.setPixel(x, y, 255);
              changed = true;
            }
          }
        }
      }
    }

    // Remove weak edges not connected to strong ones
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        if (result.getPixel(x, y) == 128) {
          result.setPixel(x, y, 0);
        }
      }
    }

    return result;
  }
}

/// Helper class to store gradient data.
class _GradientData {
  final ImageMatrix magnitude;
  final List<List<double>> direction;

  _GradientData(this.magnitude, this.direction);
}

/// Holds the result of the captcha solving process.
class PuzzleCaptchaResult {
  final int _x;
  final int _y;
  final ImageMatrix _backgroundImage;
  final ImageMatrix _puzzleImage;
  final double _elapsedTime;

  PuzzleCaptchaResult(
    this._x,
    this._y,
    this._backgroundImage,
    this._puzzleImage,
    this._elapsedTime,
  );

  int get x => _x;

  int get y => _y;

  ImageMatrix get backgroundImage => _backgroundImage;

  ImageMatrix get puzzleImage => _puzzleImage;

  double get elapsedTime => _elapsedTime;

  @override
  String toString() =>
      'PuzzleCaptchaResult(x: $x, y: $y, elapsed: ${elapsedTime.toStringAsFixed(3)}s)';
}

class _MatchResult {
  final double value;
  final int x;
  final int y;

  _MatchResult(this.value, this.x, this.y);
}

/// Solves puzzle captchas by applying transformations and template matching.
class PuzzleCaptchaSolver {
  static const int minImageSize = 4;
  static const int maxImageSize = 8192;

  final List<ImageTransform> transforms;

  PuzzleCaptchaSolver([List<ImageTransform>? customTransforms])
    : transforms =
          customTransforms ?? [NormalizeTransform(), EdgeTransform(150, 250)];

  /// Solves captcha from raw image bytes.
  PuzzleCaptchaResult handleBytes(
    Uint8List backgroundBytes,
    Uint8List puzzleBytes,
  ) {
    final background = ImageMatrix.fromBytes(backgroundBytes);
    final puzzle = ImageMatrix.fromBytes(puzzleBytes);
    return handleImage(background, puzzle);
  }

  /// Processes in-memory images and find the puzzle position.
  PuzzleCaptchaResult handleImage(ImageMatrix background, ImageMatrix puzzle) {
    _validateImages(background, puzzle);

    final stopwatch = Stopwatch()..start();

    final processedBackground = _applyTransforms(background);
    final processedPuzzle = _applyTransforms(puzzle);

    final matchResult = _matchTemplate(processedBackground, processedPuzzle);

    stopwatch.stop();
    final elapsedTime = stopwatch.elapsedMicroseconds / 1000000.0;

    return PuzzleCaptchaResult(
      matchResult.x,
      matchResult.y,
      background,
      puzzle,
      elapsedTime,
    );
  }

  ImageMatrix _applyTransforms(ImageMatrix image) {
    ImageMatrix processed = image;
    for (final transform in transforms) {
      processed = transform.transform(processed);
    }
    return processed;
  }

  _MatchResult _matchTemplate(ImageMatrix background, ImageMatrix template) {
    final bgHeight = background.height;
    final bgWidth = background.width;
    final tplHeight = template.height;
    final tplWidth = template.width;

    double bestMatch = -2.0;
    int bestX = 0;
    int bestY = 0;

    // Pre-calculate template statistics for efficiency
    double templateMean = 0.0;
    final templatePixelCount = tplHeight * tplWidth;

    // Calculate template mean
    for (int y = 0; y < tplHeight; y++) {
      for (int x = 0; x < tplWidth; x++) {
        templateMean += template.getPixel(x, y);
      }
    }
    templateMean /= templatePixelCount;

    // Slide the template over the background image
    for (int y = 0; y <= bgHeight - tplHeight; y++) {
      for (int x = 0; x <= bgWidth - tplWidth; x++) {
        final correlation = _calculateOptimizedCorrelation(
          background,
          template,
          x,
          y,
          templateMean,
        );

        if (correlation > bestMatch) {
          bestMatch = correlation;
          bestX = x;
          bestY = y;
        }
      }
    }

    return _MatchResult(bestMatch, bestX, bestY);
  }

  double _calculateOptimizedCorrelation(
    ImageMatrix background,
    ImageMatrix template,
    int offsetX,
    int offsetY,
    double templateMean,
  ) {
    final tplHeight = template.height;
    final tplWidth = template.width;
    final pixelCount = tplHeight * tplWidth;

    // Calculate background window mean
    double bgMean = 0.0;
    for (int y = 0; y < tplHeight; y++) {
      for (int x = 0; x < tplWidth; x++) {
        bgMean += background.getPixel(offsetX + x, offsetY + y).toDouble();
      }
    }
    bgMean /= pixelCount;

    // Calculate correlation components
    double numerator = 0.0;
    double bgSumSquares = 0.0;
    double tplSumSquares = 0.0;

    for (int y = 0; y < tplHeight; y++) {
      for (int x = 0; x < tplWidth; x++) {
        final bgPixel = background
            .getPixel(offsetX + x, offsetY + y)
            .toDouble();
        final tplPixel = template.getPixel(x, y).toDouble();

        final bgDiff = bgPixel - bgMean;
        final tplDiff = tplPixel - templateMean;

        numerator += bgDiff * tplDiff;
        bgSumSquares += bgDiff * bgDiff;
        tplSumSquares += tplDiff * tplDiff;
      }
    }

    final denominator = math.sqrt(bgSumSquares * tplSumSquares);
    if (denominator < 1e-10) {
      return 0.0; // Avoid division by zero
    }

    // Return normalized correlation coefficient
    return numerator / denominator;
  }

  void _validateImages(ImageMatrix background, ImageMatrix puzzle) {
    final bgHeight = background.height;
    final bgWidth = background.width;
    final pzHeight = puzzle.height;
    final pzWidth = puzzle.width;

    if (bgWidth < minImageSize || bgHeight < minImageSize) {
      throw ArgumentError(
        'Background image size (${bgWidth}x$bgHeight) is too small',
      );
    }

    if (bgWidth > maxImageSize || bgHeight > maxImageSize) {
      throw ArgumentError(
        'Background image size (${bgWidth}x$bgHeight) is too large',
      );
    }

    if (pzWidth < minImageSize || pzHeight < minImageSize) {
      throw ArgumentError(
        'Puzzle image size (${pzWidth}x$pzHeight) is too small',
      );
    }

    if (pzWidth > maxImageSize || pzHeight > maxImageSize) {
      throw ArgumentError(
        'Puzzle image size (${pzWidth}x$pzHeight) is too large',
      );
    }

    if (pzWidth > bgWidth || pzHeight > bgHeight) {
      throw ArgumentError(
        'Puzzle (${pzWidth}x$pzHeight) is larger than background (${bgWidth}x$bgHeight)',
      );
    }
  }
}
