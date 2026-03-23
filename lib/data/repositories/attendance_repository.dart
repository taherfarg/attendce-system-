import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/error_handler.dart';
import '../models/attendance_model.dart';
import 'package:flutter/foundation.dart';

class AttendanceRepository {
  final SupabaseClient _client = Supabase.instance.client;
  static const String _historyCacheKey = 'attendance_history_cache';

  Future<void> checkIn({
    required String userId,
    List<double>? faceEmbedding,
    String? qrCode,
    required Map<String, dynamic> location,
    required Map<String, dynamic> wifiInfo,
  }) async {
    try {
      try { await _client.auth.refreshSession(); } catch (_) {}
      final response = await _client.functions.invoke(
        'verify_attendance',
        body: {
          'user_id': userId,
          if (faceEmbedding != null) 'face_embedding': faceEmbedding,
          if (qrCode != null) 'qr_code': qrCode,
          'location': location,
          'wifi_info': wifiInfo,
          'type': 'check_in',
        },
      );

      if (response.status != 200) {
        throw response.data?.toString() ?? 'Unknown error from server';
      }
    } catch (e) {
      debugPrint('Check-in Error: $e');
      throw AppErrorHandler.parse(e);
    }
  }

  Future<void> checkOut({
    required String userId,
    List<double>? faceEmbedding,
    String? qrCode,
    required Map<String, dynamic> location,
    required Map<String, dynamic> wifiInfo,
  }) async {
    try {
      try { await _client.auth.refreshSession(); } catch (_) {}
      final response = await _client.functions.invoke(
        'verify_attendance',
        body: {
          'user_id': userId,
          if (faceEmbedding != null) 'face_embedding': faceEmbedding,
          if (qrCode != null) 'qr_code': qrCode,
          'location': location,
          'wifi_info': wifiInfo,
          'type': 'check_out',
        },
      );

      if (response.status != 200) {
        throw response.data?.toString() ?? 'Unknown error from server';
      }
    } catch (e) {
      debugPrint('Check-out Error: $e');
      throw AppErrorHandler.parse(e);
    }
  }

  /// Returns sorted list of attendance history (with local cache fallback)
  Future<List<AttendanceModel>> getHistory() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw 'User not authenticated';

      try {
        final List<dynamic> data = await _client
            .from('attendance')
            .select()
            .eq('user_id', userId)
            .order('check_in_time', ascending: false);

        // Save successfully fetched data to local cache
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_historyCacheKey, jsonEncode(data));

        return data.map((json) => AttendanceModel.fromJson(json)).toList();
      } catch (networkError) {
        // Fallback to offline cache if network request fails
        final prefs = await SharedPreferences.getInstance();
        final cachedData = prefs.getString(_historyCacheKey);
        
        if (cachedData != null) {
          debugPrint('Network error. Returning offline history cache.');
          final List<dynamic> decodedCache = jsonDecode(cachedData);
          return decodedCache.map((json) => AttendanceModel.fromJson(json)).toList();
        }
        
        // Throw original error if no cache is available
        throw networkError;
      }
    } catch (e) {
      debugPrint('Fetch History Error: $e');
      throw AppErrorHandler.parse(e);
    }
  }
}
