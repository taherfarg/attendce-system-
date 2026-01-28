import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Application configuration loaded from environment variables
class AppConfig {
  static String get supabaseUrl =>
      dotenv.env['SUPABASE_URL'] ?? 'https://qcdggtrveyzhmphjjukg.supabase.co';
  static String get supabaseAnonKey =>
      dotenv.env['SUPABASE_ANON_KEY'] ??
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFjZGdndHJ2ZXl6aG1waGpqdWtnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcxODI1NjgsImV4cCI6MjA4Mjc1ODU2OH0.obfeKglwTkM8cqRfghJ7fNaolQTCJVQ504Mndkp7qdc';

  /// Initialize configuration - must be called before runApp
  static Future<void> initialize() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (e) {
      // Ignore error and check if env vars are hardcoded (fallback)
      print('Warning: Could not load .env file: $e');
    }
  }
}
