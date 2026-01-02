import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Application configuration loaded from environment variables
class AppConfig {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  /// Initialize configuration - must be called before runApp
  static Future<void> initialize() async {
    await dotenv.load(fileName: '.env');

    // Validate required config
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw Exception(
        'Missing environment configuration. '
        'Please ensure .env file exists with SUPABASE_URL and SUPABASE_ANON_KEY.',
      );
    }
  }
}
