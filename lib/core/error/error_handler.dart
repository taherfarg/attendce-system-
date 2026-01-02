import 'package:flutter/material.dart';
import 'exceptions.dart';
import '../auth/auth_service.dart';

/// Centralized error handler for consistent error messages and actions
class ErrorHandler {
  /// Convert any exception to a user-friendly message
  static String getMessage(dynamic error) {
    if (error is AuthException) {
      return error.message;
    } else if (error is AttendanceException) {
      return _getAttendanceMessage(error);
    } else if (error is LocationException) {
      return 'Location error: ${error.message}';
    } else if (error is WiFiException) {
      return 'WiFi error: ${error.message}';
    } else if (error is FaceException) {
      return 'Face verification error: ${error.message}';
    } else if (error is NetworkException) {
      return 'Network error: ${error.message}';
    } else if (error is ServerException) {
      return 'Server error: ${error.message}';
    } else if (error is Exception) {
      return error.toString().replaceFirst('Exception: ', '');
    }
    return 'An unexpected error occurred';
  }

  /// Get user-friendly message for attendance errors
  static String _getAttendanceMessage(AttendanceException error) {
    switch (error.errorType) {
      case 'LOCATION_INVALID':
        return error.message;
      case 'WIFI_INVALID':
        return error.message;
      case 'FACE_MISMATCH':
        return 'Face verification failed. Please try again.';
      case 'NO_FACE_PROFILE':
        return 'Please complete face enrollment first.';
      case 'NO_ACTIVE_CHECKIN':
        return 'No active check-in found. Please check in first.';
      case 'EMBEDDING_MISMATCH':
        return 'Face data error. Please re-enroll your face.';
      default:
        return error.message;
    }
  }

  /// Show an error snackbar
  static void showError(BuildContext context, dynamic error) {
    final message = getMessage(error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Show a success snackbar
  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Show a warning snackbar
  static void showWarning(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_outlined, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange.shade600,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Parse Edge Function response errors
  static AttendanceException? parseAttendanceError(
    Map<String, dynamic> response,
  ) {
    if (response['success'] == false && response['error'] != null) {
      return AttendanceException(
        response['message'] as String? ?? 'Unknown error',
        errorType: response['error'] as String,
      );
    }
    return null;
  }
}
