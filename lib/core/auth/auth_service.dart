import 'package:supabase_flutter/supabase_flutter.dart';

/// Custom exception for authentication errors
class AuthException implements Exception {
  final String message;
  final String? code;
  AuthException(this.message, {this.code});

  @override
  String toString() =>
      'AuthException: $message${code != null ? ' (code: $code)' : ''}';
}

/// Service for handling all authentication operations
class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Current user's ID or null if not logged in
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Current user's email or null if not logged in
  String? get currentUserEmail => _client.auth.currentUser?.email;

  /// Check if user is currently logged in
  bool get isLoggedIn => _client.auth.currentUser != null;

  /// Sign in with email and password
  Future<void> signIn(String email, String password) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (response.user == null) {
        throw AuthException('Login failed: No user returned');
      }
    } on AuthApiException catch (e) {
      throw AuthException(_parseAuthError(e.message), code: e.statusCode);
    }
  }

  /// Sign up a new user with email and password
  Future<void> signUp(String email, String password, {String? name}) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: name != null ? {'name': name} : null,
      );

      if (response.user == null) {
        throw AuthException('Sign up failed: No user returned');
      }

      // Create user profile in public.users table
      await _client.from('users').insert({
        'id': response.user!.id,
        'name': name ?? email.split('@')[0],
        'role': 'employee',
        'status': 'active',
      });
    } on AuthApiException catch (e) {
      throw AuthException(_parseAuthError(e.message), code: e.statusCode);
    } on PostgrestException catch (e) {
      throw AuthException('Failed to create user profile: ${e.message}');
    }
  }

  /// Send password reset email
  Future<void> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim());
    } on AuthApiException catch (e) {
      throw AuthException(_parseAuthError(e.message), code: e.statusCode);
    }
  }

  /// Sign out current user
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Check if current user has admin role
  Future<bool> isAdmin() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    try {
      final response = await _client
          .from('users')
          .select('role')
          .eq('id', user.id)
          .single();

      return response['role'] == 'admin';
    } catch (e) {
      return false;
    }
  }

  /// Get current user's role
  Future<String?> getCurrentUserRole() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final response = await _client
          .from('users')
          .select('role')
          .eq('id', user.id)
          .single();

      return response['role'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Parse Supabase auth errors into user-friendly messages
  String _parseAuthError(String message) {
    if (message.contains('Invalid login credentials')) {
      return 'Invalid email or password';
    } else if (message.contains('Email not confirmed')) {
      return 'Please verify your email before logging in';
    } else if (message.contains('User already registered')) {
      return 'An account with this email already exists';
    } else if (message.contains('Password should be')) {
      return 'Password must be at least 6 characters';
    } else if (message.contains('rate limit')) {
      return 'Too many attempts. Please try again later';
    }
    return message;
  }
}
