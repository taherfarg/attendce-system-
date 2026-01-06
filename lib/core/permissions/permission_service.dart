import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Simple permission helper that checks status before requesting
/// to avoid the "A request for permissions is already running" error
class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  // Track which permissions are currently being requested
  final Set<Permission> _pendingRequests = {};

  /// Request a permission safely - checks if already granted or pending
  Future<PermissionStatus> requestPermission(Permission permission) async {
    // Fast path: check if already granted
    var status = await permission.status;
    if (status.isGranted) {
      return status;
    }

    // If a request for this permission is already pending, wait and check status
    if (_pendingRequests.contains(permission)) {
      debugPrint(
        'PermissionService: $permission request already pending, waiting...',
      );
      // Wait for the pending request to complete
      await Future.delayed(const Duration(milliseconds: 500));
      // Return current status after waiting
      return await permission.status;
    }

    // Mark as pending and request
    _pendingRequests.add(permission);
    try {
      debugPrint('PermissionService: Requesting $permission');
      status = await permission.request();
      debugPrint('PermissionService: $permission result: $status');
      return status;
    } catch (e) {
      debugPrint('PermissionService: Error requesting $permission: $e');
      // On error, return current status
      return await permission.status;
    } finally {
      _pendingRequests.remove(permission);
    }
  }

  /// Check if permission is granted without requesting
  Future<bool> isGranted(Permission permission) async {
    final status = await permission.status;
    return status.isGranted;
  }
}
