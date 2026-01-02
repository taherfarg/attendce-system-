/// Base exception for app-specific errors
abstract class AppException implements Exception {
  final String message;
  final String? code;

  AppException(this.message, {this.code});

  @override
  String toString() => '$runtimeType: $message';
}

/// Exception for location-related errors
class LocationException extends AppException {
  LocationException(super.message, {super.code});
}

/// Exception for WiFi-related errors
class WiFiException extends AppException {
  WiFiException(super.message, {super.code});
}

/// Exception for face recognition errors
class FaceException extends AppException {
  FaceException(super.message, {super.code});
}

/// Exception for network/connectivity errors
class NetworkException extends AppException {
  NetworkException(super.message, {super.code});
}

/// Exception for attendance/check-in errors
class AttendanceException extends AppException {
  final String errorType;

  AttendanceException(super.message, {required this.errorType, super.code});

  /// Check if this is a recoverable error
  bool get isRecoverable {
    return errorType != 'NO_FACE_PROFILE';
  }
}

/// Exception for server-side errors
class ServerException extends AppException {
  final int? statusCode;

  ServerException(super.message, {this.statusCode, super.code});
}
