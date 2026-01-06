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

    // Check if face is centered - more relaxed thresholds
    // X: anywhere between 15% and 85% of width (very generous)
    // Y: anywhere between 10% and 90% of height (very generous)
    final isCentered =
        (faceCenterX > 0.15 && faceCenterX < 0.85) &&
        (faceCenterY > 0.1 && faceCenterY < 0.9);

    // Check face size (should be 10-80% of image) - more relaxed
    final faceRatio = boundingBox.width / imageSize.width;
    final isSizeOk = faceRatio > 0.10 && faceRatio < 0.80;

    // Check head rotation - more relaxed
    final headEulerAngleY = face.headEulerAngleY ?? 0; // Left/right rotation
    final headEulerAngleZ = face.headEulerAngleZ ?? 0; // Tilt
    final isHeadStraight =
        headEulerAngleY.abs() < 35 && headEulerAngleZ.abs() < 25;

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
    final box = face.boundingBox;

    // Normalization factors
    final centerX = box.center.dx;
    final centerY = box.center.dy;
    final width = box.width;
    final height = box.height;

    List<double> embedding = [];

    // Helper to normalize and add point
    void addNormalizedPoint(int x, int y) {
      // Normalize to range approximately -0.5 to 0.5
      embedding.add((x - centerX) / width);
      embedding.add((y - centerY) / height);
    }

    // Add landmark positions (normalized)
    for (final type in FaceLandmarkType.values) {
      final landmark = landmarks[type];
      if (landmark != null) {
        addNormalizedPoint(landmark.position.x, landmark.position.y);
      } else {
        embedding.add(0);
        embedding.add(0);
      }
    }

    // Add face geometry (angles only, size is irrelevant for identity)
    embedding.add(face.headEulerAngleX ?? 0);
    embedding.add(face.headEulerAngleY ?? 0);
    embedding.add(face.headEulerAngleZ ?? 0);

    // Add contour points (normalized)
    // We only take a subset of points to keep embedding size manageable
    for (final type in FaceContourType.values) {
      final contour = contours[type];
      if (contour != null && contour.points.isNotEmpty) {
        // Add every 5th point to reduce dimensionality but capture shape
        for (var i = 0; i < contour.points.length; i += 4) {
          addNormalizedPoint(contour.points[i].x, contour.points[i].y);
        }
      } else {
        // If contour is missing, add placeholders to maintain embedding size consistency
        // The number of placeholders should match the expected number of points if present
        // For simplicity, assuming 4 points (2 coordinates each) if a contour is missing
        embedding.addAll(
          [0, 0, 0, 0, 0, 0, 0, 0],
        ); // Adjusted to match potential 4 points (every 5th point from original)
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

  /// Calculate embedding quality score (0.0 to 1.0)
  /// Based on how many landmarks and contours were available
  double calculateEmbeddingQuality(Face face) {
    int availableLandmarks = 0;
    int availableContours = 0;

    for (final type in FaceLandmarkType.values) {
      if (face.landmarks[type] != null) availableLandmarks++;
    }
    for (final type in FaceContourType.values) {
      if (face.contours[type] != null) availableContours++;
    }

    final landmarkScore = availableLandmarks / FaceLandmarkType.values.length;
    final contourScore = availableContours / FaceContourType.values.length;

    // Weight: 40% landmarks, 60% contours (contours give better shape info)
    return (landmarkScore * 0.4) + (contourScore * 0.6);
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

  /// Calculate cosine similarity between two embeddings (-1.0 to 1.0, higher is more similar)
  double cosineSimilarity(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) {
      throw FaceException('Embedding dimension mismatch');
    }

    double dotProduct = 0;
    double norm1 = 0;
    double norm2 = 0;

    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
      norm1 += embedding1[i] * embedding1[i];
      norm2 += embedding2[i] * embedding2[i];
    }

    if (norm1 == 0 || norm2 == 0) return 0;
    return dotProduct / (sqrt(norm1) * sqrt(norm2));
  }

  /// Average multiple embeddings into one (for verification stability)
  List<double> averageEmbeddings(List<List<double>> embeddings) {
    if (embeddings.isEmpty) {
      throw FaceException('No embeddings to average');
    }
    if (embeddings.length == 1) return embeddings.first;

    final length = embeddings.first.length;
    final averaged = List<double>.filled(length, 0);

    for (final emb in embeddings) {
      for (int i = 0; i < length; i++) {
        averaged[i] += emb[i];
      }
    }

    for (int i = 0; i < length; i++) {
      averaged[i] /= embeddings.length;
    }

    return averaged;
  }

  /// Compare embedding against multiple stored embeddings
  /// Returns the best (lowest) distance found
  FaceMatchResult compareAgainstAll(
    List<double> incoming,
    List<List<double>> storedEmbeddings, {
    double threshold = 0.8,
  }) {
    if (storedEmbeddings.isEmpty) {
      throw FaceException('No stored embeddings to compare against');
    }

    double bestDistance = double.infinity;
    double bestCosine = -1;
    int bestIndex = 0;

    for (int i = 0; i < storedEmbeddings.length; i++) {
      final distance = compareEmbeddings(incoming, storedEmbeddings[i]);
      final cosine = cosineSimilarity(incoming, storedEmbeddings[i]);

      if (distance < bestDistance) {
        bestDistance = distance;
        bestCosine = cosine;
        bestIndex = i;
      }
    }

    return FaceMatchResult(
      isMatch: bestDistance < threshold,
      bestDistance: bestDistance,
      bestCosine: bestCosine,
      matchedIndex: bestIndex,
      totalCompared: storedEmbeddings.length,
    );
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

/// Result of comparing against multiple stored embeddings
class FaceMatchResult {
  final bool isMatch;
  final double bestDistance;
  final double bestCosine;
  final int matchedIndex;
  final int totalCompared;

  FaceMatchResult({
    required this.isMatch,
    required this.bestDistance,
    required this.bestCosine,
    required this.matchedIndex,
    required this.totalCompared,
  });
}
