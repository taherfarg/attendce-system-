import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for managing offline attendance queue
class OfflineQueueService {
  static Database? _database;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription? _connectivitySubscription;

  /// Initialize the database
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'attendance_queue.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pending_attendance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            type TEXT NOT NULL,
            face_embedding TEXT NOT NULL,
            location_lat REAL NOT NULL,
            location_lng REAL NOT NULL,
            wifi_ssid TEXT,
            wifi_bssid TEXT,
            created_at TEXT NOT NULL,
            retry_count INTEGER DEFAULT 0,
            last_error TEXT
          )
        ''');
      },
    );
  }

  /// Queue an attendance record for later sync
  Future<int> queueAttendance({
    required String userId,
    required String type,
    required List<double> faceEmbedding,
    required Map<String, dynamic> location,
    required Map<String, dynamic> wifiInfo,
  }) async {
    final db = await database;

    return await db.insert('pending_attendance', {
      'user_id': userId,
      'type': type,
      'face_embedding': jsonEncode(faceEmbedding),
      'location_lat': location['lat'],
      'location_lng': location['lng'],
      'wifi_ssid': wifiInfo['ssid'],
      'wifi_bssid': wifiInfo['bssid'],
      'created_at': DateTime.now().toIso8601String(),
      'retry_count': 0,
    });
  }

  /// Get all pending attendance records
  Future<List<Map<String, dynamic>>> getPendingRecords() async {
    final db = await database;
    return await db.query('pending_attendance', orderBy: 'created_at ASC');
  }

  /// Get count of pending records
  Future<int> getPendingCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM pending_attendance',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Delete a synced record
  Future<void> deleteRecord(int id) async {
    final db = await database;
    await db.delete('pending_attendance', where: 'id = ?', whereArgs: [id]);
  }

  /// Update retry count and error for a record
  Future<void> updateRetryInfo(int id, String error) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE pending_attendance SET retry_count = retry_count + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
  }

  /// Sync all pending records with server
  Future<SyncResult> syncPendingRecords() async {
    final pending = await getPendingRecords();
    int synced = 0;
    int failed = 0;
    List<String> errors = [];

    final client = Supabase.instance.client;

    for (final record in pending) {
      try {
        final response = await client.functions.invoke(
          'verify_attendance',
          body: {
            'user_id': record['user_id'],
            'face_embedding': jsonDecode(record['face_embedding']),
            'location': {
              'lat': record['location_lat'],
              'lng': record['location_lng'],
            },
            'wifi_info': {
              'ssid': record['wifi_ssid'],
              'bssid': record['wifi_bssid'],
            },
            'type': record['type'],
          },
        );

        if (response.status == 200) {
          await deleteRecord(record['id'] as int);
          synced++;
        } else {
          await updateRetryInfo(record['id'] as int, response.data.toString());
          failed++;
          errors.add('Record ${record['id']}: ${response.data}');
        }
      } catch (e) {
        await updateRetryInfo(record['id'] as int, e.toString());
        failed++;
        errors.add('Record ${record['id']}: $e');
      }
    }

    return SyncResult(
      total: pending.length,
      synced: synced,
      failed: failed,
      errors: errors,
    );
  }

  /// Start listening for connectivity changes to auto-sync
  void startAutoSync() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      results,
    ) async {
      // Check if we have any connection
      final hasConnection = results != ConnectivityResult.none;

      if (hasConnection) {
        final pendingCount = await getPendingCount();
        if (pendingCount > 0) {
          await syncPendingRecords();
        }
      }
    });
  }

  /// Stop auto-sync
  void stopAutoSync() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  /// Check if device is online
  Future<bool> isOnline() async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  /// Dispose resources
  void dispose() {
    stopAutoSync();
    _database?.close();
    _database = null;
  }
}

/// Result of sync operation
class SyncResult {
  final int total;
  final int synced;
  final int failed;
  final List<String> errors;

  SyncResult({
    required this.total,
    required this.synced,
    required this.failed,
    required this.errors,
  });

  bool get isSuccess => failed == 0;
}
