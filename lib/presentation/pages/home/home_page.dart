import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/services/offline_queue.dart';
import '../attendance/face_scan_page.dart';
import '../attendance/qr_scan_page.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/models/attendance_model.dart';
import '../../../core/utils/time_utils.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/wifi_service.dart';
import 'package:geolocator/geolocator.dart';

// Tabs
import 'tabs/dashboard_tab.dart';
import 'tabs/history_tab.dart';
import 'tabs/profile_tab.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _authService = AuthService();
  final _repo = AttendanceRepository();
  final _offlineQueue = OfflineQueueService();
  final _locationService = LocationService();
  final _wifiService = WifiService();

  int _currentIndex = 0;
  List<AttendanceModel> _history = [];
  bool _isLoading = true;
  AttendanceModel? _todayRecord;
  String _userName = '';

  // Stats
  int _weeklyMinutes = 0;
  int _daysPresent = 0;
  List<bool> _weekDays = List.filled(7, false); // Mon-Sun

  // Live timer
  Timer? _liveTimer;
  Duration _elapsedTime = Duration.zero;

  // System Settings
  Map<String, dynamic> _systemSettings = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // 1. User Name
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        final userData = await Supabase.instance.client
            .from('users')
            .select('name')
            .eq('id', userId)
            .maybeSingle();
        _userName = userData?['name'] ?? 'Employee';
      }

      // 2. History & Offline Queue
      final data = await _repo.getHistory();
      // We could check pending offline queue here if needed for sync status

      // 3. System Settings
      final settingsData = await Supabase.instance.client
          .from('system_settings')
          .select('setting_key, setting_value');

      final Map<String, dynamic> settingsMap = {};
      for (var item in settingsData) {
        settingsMap[item['setting_key']] = item['setting_value'];
      }

      // 4. Calculate Stats
      final now = TimeUtils.nowDubai();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final startOfWeek = DateTime(
        weekStart.year,
        weekStart.month,
        weekStart.day,
      );

      int weeklyMinutes = 0;
      Set<int> presentDays = {};
      List<bool> weekDays = List.filled(7, false);

      for (var record in data) {
        final checkIn = TimeUtils.toDubai(record.checkInTime);
        if (checkIn.isAfter(startOfWeek)) {
          weeklyMinutes += record.totalMinutes;
          final dayIndex = checkIn.weekday - 1;
          if (dayIndex >= 0 && dayIndex < 7) {
            weekDays[dayIndex] = true;
            presentDays.add(checkIn.day);
          }
        }
      }

      // 5. Today's Record
      final todayRecords = data.where((r) {
        final checkIn = TimeUtils.toDubai(r.checkInTime);
        return checkIn.year == now.year &&
            checkIn.month == now.month &&
            checkIn.day == now.day;
      }).toList();

      AttendanceModel? statusRecord;
      if (todayRecords.isNotEmpty) {
        try {
          // Prefer active session
          statusRecord = todayRecords.firstWhere((r) => r.checkOutTime == null);
        } catch (_) {
          // Or show the most recent completed
          statusRecord = todayRecords.first;
        }
      }

      if (mounted) {
        setState(() {
          _history = data;
          _todayRecord = statusRecord;
          _weeklyMinutes = weeklyMinutes;
          _daysPresent = presentDays.length;
          _weekDays = weekDays;
          _systemSettings = settingsMap;
          _isLoading = false;
        });
        _startLiveTimer();
      }
    } catch (e) {
      debugPrint("Error loading data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startLiveTimer() {
    _liveTimer?.cancel();
    if (_todayRecord != null && _todayRecord!.isCheckedIn) {
      final checkIn = TimeUtils.toDubai(_todayRecord!.checkInTime);
      final now = TimeUtils.nowDubai();
      _elapsedTime = now.difference(checkIn);

      _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _elapsedTime += const Duration(seconds: 1);
          });
        }
      });
    } else {
      _elapsedTime = Duration.zero;
    }
  }

  // --- Check In/Out Logic ---

  Future<void> _validateAndProceed(bool isCheckIn) async {
    // Show validation loader
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 3),
              SizedBox(width: 20),
              Text('Verifying Location & WiFi...'),
            ],
          ),
        ),
      ),
    );

    try {
      final officeLat = _systemSettings['office_location']?['lat'];
      final officeLng = _systemSettings['office_location']?['lng'];
      final allowedRadius = _systemSettings['allowed_radius_meters'] ?? 100;
      final wifiAllowList =
          (_systemSettings['wifi_allowlist'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      // Location Check
      if (officeLat != null && officeLng != null) {
        final position = await _locationService.getCurrentPosition();
        final distance = _locationService.calculateDistance(
          position.latitude,
          position.longitude,
          officeLat,
          officeLng,
        );

        if (distance > allowedRadius) {
          throw 'You are too far from the office.\nDistance: ${distance.toStringAsFixed(0)}m (Max: ${allowedRadius}m)';
        }
      }

      // WiFi Check
      if (wifiAllowList.isNotEmpty) {
        final currentSsid = await _wifiService.getCurrentWifiSsid();
        if (currentSsid == null || !wifiAllowList.contains(currentSsid)) {
          throw 'You must be connected to office WiFi.\nCurrent: ${currentSsid ?? 'Unknown'}';
        }
      }

      if (mounted) Navigator.pop(context); // Close loader

      if (mounted) {
        _showVerificationSheet(isCheckIn);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close loader
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Validation Failed'),
            content: Text(e.toString().replaceAll('Exception: ', '')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _showVerificationSheet(bool isCheckIn) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCheckIn ? 'Check In Method' : 'Check Out Method',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.face_rounded, color: Colors.blue),
              ),
              title: const Text('Face Verification'),
              subtitle: const Text('Secure biometric verification'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FaceScanPage(isCheckIn: isCheckIn),
                  ),
                ).then((_) => _loadData());
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.qr_code_rounded, color: Colors.teal),
              ),
              title: const Text('Scan QR Code'),
              subtitle: const Text('Scan office QR code'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QrScanPage(isCheckIn: isCheckIn),
                  ),
                ).then((_) => _loadData());
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final List<Widget> tabs = [
      DashboardTab(
        userName: _userName,
        isCheckedIn: _todayRecord?.isCheckedIn ?? false,
        isComplete: _todayRecord?.isComplete ?? false,
        elapsedTime: _elapsedTime,
        todayRecord: _todayRecord,
        weeklyMinutes: _weeklyMinutes,
        daysPresent: _daysPresent,
        weekDays: _weekDays,
        onCheckIn: () => _validateAndProceed(true),
        onCheckOut: () => _validateAndProceed(false),
        isLoading: _isLoading,
      ),
      HistoryTab(history: _history, isLoading: _isLoading),
      ProfileTab(
        userName: _userName,
        history: _history,
        onLogout: () => _authService.signOut(),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: IndexedStack(index: _currentIndex, children: tabs),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          backgroundColor: Colors.white,
          indicatorColor: scheme.primary.withOpacity(0.1),
          height: 65,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_rounded),
              selectedIcon: Icon(Icons.history_toggle_off),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
