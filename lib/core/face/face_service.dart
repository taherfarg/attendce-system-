import 'dart:typed_data';
import 'dart:ui' show Size;
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';

/// Service for face detection, liveness check, and embedding extraction
class FaceService {
  late FaceDetector _faceDetector;
  bool _isInitialized = false;

  /// Initialize face detector with options
  Future<void> initialize() async {
    if (_isInitialized) return;

    final options = FaceDetectorOptions(
      enableClassification: true, // For blink detection
      enableLandmarks: true, // For face alignment
      enableContours: true, // For face shape
      enableTracking: true, // For tracking same face
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.15,
    );

    _faceDetector = FaceDetector(options: options);
    _isInitialized = true;
  }

  /// Dispose resources
  Future<void> dispose() async {
    if (_isInitialized) {
      await _faceDetector.close();
      _isInitialized = false;
    }
  }

  /// Convert CameraImage to InputImage for ML Kit
  InputImage? convertCameraImageToInputImage(
    CameraImage image,
    CameraDescription camera,
    int sensorOrientation,
  ) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final rotation = _getInputImageRotation(
      camera.lensDirection,
      sensorOrientation,
    );
    if (rotation == null) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  InputImageRotation? _getInputImageRotation(
    CameraLensDirection lensDirection,
    int sensorOrientation,
  ) {
    final orientations = {
      0: InputImageRotation.rotation0deg,
      90: InputImageRotation.rotation90deg,
      180: InputImageRotation.rotation180deg,
      270: InputImageRotation.rotation270deg,
    };

    return orientations[sensorOrientation];
  }

  /// Detect faces in an image
  Future<List<Face>> detectFaces(InputImage inputImage) async {
    if (!_isInitialized) {
      await initialize();
    }
    return await _faceDetector.processImage(inputImage);
  }

  /// Check liveness by detecting eye blink
  LivenessResult checkLiveness(Face face) {
    final leftEyeOpen = face.leftEyeOpenProbability ?? 1.0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 1.0;
    final isSmiling = face.smilingProbability ?? 0.0;

    // Calculate liveness score
    final eyeScore = (leftEyeOpen + rightEyeOpen) / 2;

    return LivenessResult(
      leftEyeOpen: leftEyeOpen,
      rightEyeOpen: rightEyeOpen,
      isSmiling: isSmiling,
      isBlinking: leftEyeOpen < 0.3 && rightEyeOpen < 0.3,
      eyeOpenScore: eyeScore,
    );
  }

  /// Check if face is properly aligned for capture
  FaceAlignmentResult checkFaceAlignment(Face face, Size imageSize) {
    final boundingBox = face.boundingBox;

    // Calculate face center
    final faceCenterX = boundingBox.center.dx / imageSize.width;
    final faceCenterY = boundingBox.center.dy / imageSize.height;

    // Check if face is centered (within 40% of center)
    final isCentered =
        (faceCenterX > 0.3 && faceCenterX < 0.7) &&
        (faceCenterY > 0.2 && faceCenterY < 0.6);

    // Check face size (should be 15-60% of image)
    final faceRatio = boundingBox.width / imageSize.width;
    final isSizeOk = faceRatio > 0.15 && faceRatio < 0.6;

    // Check head rotation
    final headEulerAngleY = face.headEulerAngleY ?? 0; // Left/right rotation
    final headEulerAngleZ = face.headEulerAngleZ ?? 0; // Tilt
    final isHeadStraight =
        headEulerAngleY.abs() < 20 && headEulerAngleZ.abs() < 15;

    return FaceAlignmentResult(
      isCentered: isCentered,
      isSizeOk: isSizeOk,
      isHeadStraight: isHeadStraight,
      isAligned: isCentered && isSizeOk && isHeadStraight,
      faceCenterX: faceCenterX,
      faceCenterY: faceCenterY,
      faceRatio: faceRatio,
      headRotationY: headEulerAngleY,
      headRotationZ: headEulerAngleZ,
      instruction: _getAlignmentInstruction(
        isCentered,
        isSizeOk,
        isHeadStraight,
        faceRatio,
      ),
    );
  }

  String _getAlignmentInstruction(
    bool centered,
    bool sizeOk,
    bool straight,
    double ratio,
  ) {
    if (!sizeOk) {
      return ratio < 0.15 ? 'Move closer' : 'Move back';
    }
    if (!centered) {
      return 'Move face to center';
    }
    if (!straight) {
      return 'Look straight at camera';
    }
    return 'Hold still';
  }

  /// Generate face embedding from face landmarks
  /// This is a simplified embedding - for production, use TFLite with FaceNet/ArcFace
  List<double> generateEmbedding(Face face) {
    final landmarks = face.landmarks;
    final contours = face.contours;

    List<double> embedding = [];

    // Add landmark positions (normalized)
    for (final type in FaceLandmarkType.values) {
      final landmark = landmarks[type];
      if (landmark != null) {
        embedding.add(landmark.position.x.toDouble());
        embedding.add(landmark.position.y.toDouble());
      } else {
        embedding.add(0);
        embedding.add(0);
      }
    }

    // Add face geometry
    embedding.add(face.boundingBox.width);
    embedding.add(face.boundingBox.height);
    embedding.add(face.headEulerAngleX ?? 0);
    embedding.add(face.headEulerAngleY ?? 0);
    embedding.add(face.headEulerAngleZ ?? 0);

    // Add contour points
    for (final type in FaceContourType.values) {
      final contour = contours[type];
      if (contour != null && contour.points.isNotEmpty) {
        // Add first and last points of each contour
        embedding.add(contour.points.first.x.toDouble());
        embedding.add(contour.points.first.y.toDouble());
        embedding.add(contour.points.last.x.toDouble());
        embedding.add(contour.points.last.y.toDouble());
      } else {
        embedding.addAll([0, 0, 0, 0]);
      }
    }

    // Normalize embedding to 128 dimensions
    while (embedding.length < 128) {
      embedding.add(0);
    }
    if (embedding.length > 128) {
      embedding = embedding.sublist(0, 128);
    }

    // Normalize values
    final maxVal = embedding.reduce((a, b) => a.abs() > b.abs() ? a : b).abs();
    if (maxVal > 0) {
      embedding = embedding.map((v) => v / maxVal).toList();
    }

    return embedding;
  }

  /// Compare two embeddings using Euclidean distance
  double compareEmbeddings(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) {
      throw FaceException('Embedding dimension mismatch');
    }

    double sum = 0;
    for (int i = 0; i < embedding1.length; i++) {
      sum += pow(embedding1[i] - embedding2[i], 2);
    }

    return sqrt(sum);
  }

  /// Check if two embeddings match (distance below threshold)
  bool isMatch(
    List<double> embedding1,
    List<double> embedding2, {
    double threshold = 0.8,
  }) {
    final distance = compareEmbeddings(embedding1, embedding2);
    return distance < threshold;
  }
}

/// Result of liveness detection
class LivenessResult {
  final double leftEyeOpen;
  final double rightEyeOpen;
  final double isSmiling;
  final bool isBlinking;
  final double eyeOpenScore;

  LivenessResult({
    required this.leftEyeOpen,
    required this.rightEyeOpen,
    required this.isSmiling,
    required this.isBlinking,
    required this.eyeOpenScore,
  });
}

/// Result of face alignment check
class FaceAlignmentResult {
  final bool isCentered;
  final bool isSizeOk;
  final bool isHeadStraight;
  final bool isAligned;
  final double faceCenterX;
  final double faceCenterY;
  final double faceRatio;
  final double headRotationY;
  final double headRotationZ;
  final String instruction;

  FaceAlignmentResult({
    required this.isCentered,
    required this.isSizeOk,
    required this.isHeadStraight,
    required this.isAligned,
    required this.faceCenterX,
    required this.faceCenterY,
    required this.faceRatio,
    required this.headRotationY,
    required this.headRotationZ,
    required this.instruction,
  });
}

/// Custom exception for face detection errors
class FaceException implements Exception {
  final String message;
  FaceException(this.message);

  @override
  String toString() => 'FaceException: $message';
}
