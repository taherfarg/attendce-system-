import 'dart:ui';

/// Stub for FaceDetectorOptions on web
class FaceDetectorOptions {
  final bool enableClassification;
  final bool enableLandmarks;
  final bool enableContours;
  final bool enableTracking;
  final dynamic performanceMode;
  final double minFaceSize;

  FaceDetectorOptions({
    this.enableClassification = false,
    this.enableLandmarks = false,
    this.enableContours = false,
    this.enableTracking = false,
    this.performanceMode,
    this.minFaceSize = 0.1,
  });
}

enum FaceDetectorMode { accurate, fast }

/// Stub for FaceDetector on web
class FaceDetector {
  final FaceDetectorOptions options;

  FaceDetector({required this.options});

  Future<List<Face>> processImage(InputImage image) async {
    // Return empty list on web
    return [];
  }

  Future<void> close() async {}
}

/// Stub for InputImage on web
class InputImage {
  final InputImageMetadata? metadata;

  InputImage({this.metadata});

  static InputImage fromBytes({
    required dynamic bytes,
    required InputImageMetadata metadata,
  }) {
    return InputImage(metadata: metadata);
  }
}

class InputImageMetadata {
  final Size size;
  final InputImageRotation rotation;
  final InputImageFormatValue format;
  final int bytesPerRow;

  InputImageMetadata({
    required this.size,
    required this.rotation,
    required this.format,
    required this.bytesPerRow,
  });
}

enum InputImageRotation {
  rotation0deg,
  rotation90deg,
  rotation180deg,
  rotation270deg
}

class InputImageFormatValue {
  final int raw;
  InputImageFormatValue(this.raw);

  static InputImageFormatValue? fromRawValue(int raw) {
    return InputImageFormatValue(raw);
  }
}

/// Stub for Face on web
class Face {
  final Rect boundingBox;
  final double? headEulerAngleY;
  final double? headEulerAngleZ;
  final double? headEulerAngleX;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  final double? smilingProbability;
  final Map<FaceLandmarkType, FaceLandmark> landmarks;
  final Map<FaceContourType, FaceContour> contours;

  Face({
    required this.boundingBox,
    this.headEulerAngleY,
    this.headEulerAngleZ,
    this.headEulerAngleX,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.smilingProbability,
    this.landmarks = const {},
    this.contours = const {},
  });
}

enum FaceLandmarkType {
  leftEye,
  rightEye,
  noseBase,
  leftMouth,
  rightMouth,
  bottomMouth,
  leftCheek,
  rightCheek,
  leftEar,
  rightEar
}

class FaceLandmark {
  final Point<int> position;
  final FaceLandmarkType type;

  FaceLandmark({required this.type, required this.position});
}

enum FaceContourType {
  face,
  leftEyebrowTop,
  rightEyebrowTop,
  leftEyebrowBottom,
  rightEyebrowBottom,
  leftEye,
  rightEye,
  upperLipTop,
  upperLipBottom,
  lowerLipTop,
  lowerLipBottom,
  noseBridge,
  noseBottom,
  leftCheek,
  rightCheek
}

class FaceContour {
  final FaceContourType type;
  final List<Point<int>> points;

  FaceContour({required this.type, required this.points});
}

class Point<T extends num> {
  final T x;
  final T y;

  Point(this.x, this.y);
}
