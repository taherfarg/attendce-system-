import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart'; // Replaced dart:io

class WifiService {
  final _networkInfo = NetworkInfo();

  /// Get current WiFi SSID. Returns null if not connected or permission denied.
  Future<String?> getCurrentWifiSsid() async {
    if (kIsWeb) return null; // network_info_plus doesn't support web SSID reliably

    // Request location permission for WiFi info on Android
    if (defaultTargetPlatform == TargetPlatform.android) {
      var status = await Permission.location.status;
      if (!status.isGranted) {
        status = await Permission.location.request();
        if (!status.isGranted) return null;
      }
    }

    try {
      final wifiName = await _networkInfo.getWifiName();
      // On iOS it might return the SSID in quotes, remove them
      return wifiName?.replaceAll('"', '');
    } catch (e) {
      // PlatformException if wifi info is unavailable
      return null;
    }
  }
}
