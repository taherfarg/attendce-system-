import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../permissions/permission_service.dart';

/// Service for handling WiFi network information
class WifiService {
  final NetworkInfo _networkInfo = NetworkInfo();
  final PermissionService _permissionService = PermissionService();

  /// Check and request necessary permissions for WiFi info
  Future<bool> checkAndRequestPermission() async {
    if (Platform.isAndroid) {
      // Android requires location permission to access WiFi SSID
      final status = await _permissionService.requestPermission(
        Permission.location,
      );
      return status.isGranted;
    } else if (Platform.isIOS) {
      // iOS requires location permission for WiFi info
      final status = await _permissionService.requestPermission(
        Permission.locationWhenInUse,
      );
      return status.isGranted;
    }
    return true;
  }

  /// Get current WiFi SSID (network name)
  Future<String?> getWifiName() async {
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) {
      throw WifiException('WiFi permission denied');
    }

    try {
      String? wifiName = await _networkInfo.getWifiName();
      // Remove quotes if present (Android sometimes includes them)
      if (wifiName != null) {
        wifiName = wifiName.replaceAll('"', '');
      }
      return wifiName;
    } catch (e) {
      throw WifiException('Failed to get WiFi name: $e');
    }
  }

  /// Get current WiFi BSSID (MAC address of access point)
  Future<String?> getWifiBSSID() async {
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) {
      throw WifiException('WiFi permission denied');
    }

    try {
      return await _networkInfo.getWifiBSSID();
    } catch (e) {
      throw WifiException('Failed to get WiFi BSSID: $e');
    }
  }

  /// Get complete WiFi information
  Future<WifiInfo> getWifiInfo() async {
    final ssid = await getWifiName();
    final bssid = await getWifiBSSID();

    if (ssid == null || ssid.isEmpty || ssid == '<unknown ssid>') {
      throw WifiException('Not connected to WiFi');
    }

    return WifiInfo(ssid: ssid, bssid: bssid ?? 'unknown');
  }

  /// Check if connected to allowed WiFi
  Future<WifiCheckResult> isConnectedToAllowedWifi({
    required List<String> allowedSSIDs,
  }) async {
    try {
      final wifiInfo = await getWifiInfo();
      final isAllowed = allowedSSIDs.contains(wifiInfo.ssid);

      return WifiCheckResult(
        isAllowed: isAllowed,
        currentSSID: wifiInfo.ssid,
        currentBSSID: wifiInfo.bssid,
      );
    } catch (e) {
      return WifiCheckResult(
        isAllowed: false,
        currentSSID: null,
        currentBSSID: null,
        errorMessage: e.toString(),
      );
    }
  }
}

/// WiFi network information
class WifiInfo {
  final String ssid;
  final String bssid;

  WifiInfo({required this.ssid, required this.bssid});

  Map<String, dynamic> toJson() => {'ssid': ssid, 'bssid': bssid};
}

/// Result of WiFi check against allowed list
class WifiCheckResult {
  final bool isAllowed;
  final String? currentSSID;
  final String? currentBSSID;
  final String? errorMessage;

  WifiCheckResult({
    required this.isAllowed,
    this.currentSSID,
    this.currentBSSID,
    this.errorMessage,
  });
}

/// Custom exception for WiFi errors
class WifiException implements Exception {
  final String message;
  WifiException(this.message);

  @override
  String toString() => 'WifiException: $message';
}
