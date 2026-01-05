import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

class AppErrorHandler {
  static String parse(dynamic error) {
    if (error is AuthException) {
      return _parseAuthError(error);
    } else if (error is PostgrestException) {
      return _parsePostgrestError(error);
    } else if (error is SocketException) {
      return 'No internet connection. Please check your network.';
    } else if (error is FormatException) {
      return 'Data format error. Please try again.';
    }

    // Clean up generic exception strings
    String msg = error.toString().replaceAll('Exception: ', '');
    // Remove "functions-dart" prefix if present
    if (msg.contains('functions-dart')) {
      return 'Server error. Please try again later.';
    }
    return msg;
  }

  static String _parseAuthError(AuthException error) {
    switch (error.message.toLowerCase()) {
      case 'invalid login credentials':
        return 'Invalid email or password.';
      case 'user not found':
        return 'Account does not exist.';
      case 'email not confirmed':
        return 'Please confirm your email address.';
      default:
        return error.message;
    }
  }

  static String _parsePostgrestError(PostgrestException error) {
    // RLS or DB constraint errors
    if (error.code == 'PGRST301') {
      // JWT expired or similar
      return 'Session expired. Please login again.';
    }
    return 'Database error: ${error.message}';
  }
}
