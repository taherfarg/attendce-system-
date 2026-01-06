import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/auth/auth_service.dart';
import 'admin_users_page.dart';
import 'admin_reports_page.dart';
import 'admin_settings_page.dart';
import 'admin_notifications_page.dart';
import '../profile/face_test_page.dart';
import '../../../core/utils/time_utils.dart';

/// Modern admin dashboard with attendance rate and improved layout
class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  final _authService = AuthService();

  int _todayCheckIns = 0;
  int _totalEmployees = 0;
  int _activeNow = 0;
  int _totalHoursToday = 0;
  List<Map<String, dynamic>> _liveActivity = [];
  bool _isLoading = true;
  String? _errorMessage;

  DateTime _selectedDate = DateTime.now();
  final _dateFormat = DateFormat('EEE, MMM d');

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      final client = Supabase.instance.client;
      final today = TimeUtils.nowDubai();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final startOfDayUtc = startOfDay.subtract(const Duration(hours: 4));

      // 1. Fetch Stats
      final checkInsResponse = await client
          .from('attendance')
          .select('id, total_minutes')
          .gte('check_in_time', startOfDayUtc.toIso8601String());
      _todayCheckIns = (checkInsResponse as List).length;

      // Calculate total hours today
      int totalMinutes = 0;
      for (var record in checkInsResponse) {
        totalMinutes += (record['total_minutes'] ?? 0) as int;
      }
      _totalHoursToday = totalMinutes;

      final employeesResponse = await client
          .from('users')
          .select('id')
          .eq('role', 'employee')
          .eq('status', 'active');
      _totalEmployees = (employeesResponse as List).length;

      final activeResponse = await client
          .from('attendance')
          .select('id')
          .gte('check_in_time', startOfDayUtc.toIso8601String())
          .isFilter('check_out_time', null);
      _activeNow = (activeResponse as List).length;

      // 2. Fetch Live Activity with join
      try {
        final activityResponse = await client
            .from('attendance')
            .select('*, users(name, role)')
            .gte('check_in_time', startOfDayUtc.toIso8601String())
            .order('check_in_time', ascending: false);

        if (mounted) {
          setState(() {
            _liveActivity = List<Map<String, dynamic>>.from(activityResponse);
          });
        }
      } catch (joinError) {
        debugPrint('Join failed: $joinError');
        final fallbackResponse = await client
            .from('attendance')
            .select()
            .gte('check_in_time', startOfDayUtc.toIso8601String())
            .order('check_in_time', ascending: false);

        if (mounted) {
          setState(() {
            _liveActivity = List<Map<String, dynamic>>.from(fallbackResponse);
            _errorMessage = "User details missing";
          });
        }
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  double get _attendanceRate {
    if (_totalEmployees == 0) return 0;
    return (_todayCheckIns / _totalEmployees).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDashboardData,
          color: scheme.primary,
          child: CustomScrollView(
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _dateFormat.format(TimeUtils.nowDubai()),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Admin Dashboard',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _IconBtn(
                        icon: Icons.notifications_outlined,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminNotificationsPage(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _IconBtn(
                        icon: Icons.refresh_rounded,
                        onTap: _loadDashboardData,
                        isError: _errorMessage != null,
                      ),
                      const SizedBox(width: 8),
                      _IconBtn(
                        icon: Icons.logout_rounded,
                        onTap: () => _authService.signOut(),
                        isLogout: true,
                      ),
                    ],
                  ),
                ),
              ),

              // Error Banner
              if (_errorMessage != null)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: scheme.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: scheme.error, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Stats Row + Attendance Rate
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _isLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Attendance Rate Circle
                            _AttendanceRateCard(
                              rate: _attendanceRate,
                              checkedIn: _todayCheckIns,
                              total: _totalEmployees,
                            ),
                            const SizedBox(width: 16),
                            // Stats Column
                            Expanded(
                              child: Column(
                                children: [
                                  _MiniStatCard(
                                    icon: Icons.people_rounded,
                                    value: _totalEmployees.toString(),
                                    label: 'Total Employees',
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(height: 12),
                                  _MiniStatCard(
                                    icon: Icons.circle,
                                    value: _activeNow.toString(),
                                    label: 'Currently Active',
                                    color: const Color(0xFF22C55E),
                                  ),
                                  const SizedBox(height: 12),
                                  _MiniStatCard(
                                    icon: Icons.schedule_rounded,
                                    value: '${_totalHoursToday ~/ 60}h',
                                    label: 'Total Hours Today',
                                    color: scheme.secondary,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // Quick Actions Grid
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _QuickActionCard(
                              icon: Icons.people_outline_rounded,
                              label: 'Users',
                              color: scheme.primary,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AdminUsersPage(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _QuickActionCard(
                              icon: Icons.analytics_outlined,
                              label: 'Reports',
                              color: scheme.secondary,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AdminReportsPage(),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _QuickActionCard(
                              icon: Icons.settings_outlined,
                              label: 'Settings',
                              color: const Color(0xFF8B5CF6),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AdminSettingsPage(),
                                ),
                              ),
                            ),
                          ),
                          // Face Test Removed
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // Live Activity Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.sensors_rounded,
                          color: Color(0xFFEF4444),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Live Activity',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_liveActivity.length} entries',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // Live Activity List
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: _liveActivity.isEmpty
                    ? SliverToBoxAdapter(
                        child: Container(
                          padding: const EdgeInsets.all(40),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.hourglass_empty_rounded,
                                size: 48,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _isLoading ? 'Loading...' : 'No activity today',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final record = _liveActivity[index];
                          return _ActivityCard(record: record);
                        }, childCount: _liveActivity.length),
                      ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }
}

// Icon Button
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isError;
  final bool isLogout;

  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.isError = false,
    this.isLogout = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: isLogout ? scheme.errorContainer : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isLogout
                ? null
                : Border.all(
                    color: isError ? scheme.error : Colors.grey.shade200,
                  ),
          ),
          child: Icon(
            icon,
            size: 22,
            color: isLogout
                ? scheme.error
                : (isError ? scheme.error : Colors.grey.shade700),
          ),
        ),
      ),
    );
  }
}

// Attendance Rate Card with circular progress
class _AttendanceRateCard extends StatelessWidget {
  final double rate;
  final int checkedIn;
  final int total;

  const _AttendanceRateCard({
    required this.rate,
    required this.checkedIn,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percentage = (rate * 100).round();

    return Container(
      width: 160,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: scheme.secondary.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    value: rate,
                    strokeWidth: 10,
                    backgroundColor: Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation(scheme.secondary),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$percentage%',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: scheme.secondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Attendance Rate',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$checkedIn of $total',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

// Mini Stat Card
class _MiniStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _MiniStatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Quick Action Card
class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Activity Card
class _ActivityCard extends StatelessWidget {
  final Map<String, dynamic> record;

  const _ActivityCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final userData = record['users'] as Map<String, dynamic>? ?? {};
    final checkIn = TimeUtils.toDubai(DateTime.parse(record['check_in_time']));
    final checkOutStr = record['check_out_time'];
    final checkOut = checkOutStr != null
        ? TimeUtils.toDubai(DateTime.parse(checkOutStr))
        : null;

    final duration = checkOut != null
        ? checkOut.difference(checkIn)
        : TimeUtils.nowDubai().difference(checkIn);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final durationStr = '${hours}h ${minutes}m';

    final isActive = checkOut == null;
    final name = userData['name'] ?? 'Unknown';
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';

    final timeFormat = DateFormat('HH:mm');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isActive
                    ? [scheme.secondary, scheme.secondary.withOpacity(0.7)]
                    : [Colors.grey.shade300, Colors.grey.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      timeFormat.format(checkIn),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(' → ', style: TextStyle(color: Colors.grey.shade400)),
                    Text(
                      checkOut != null ? timeFormat.format(checkOut) : 'Now',
                      style: TextStyle(
                        fontSize: 13,
                        color: isActive
                            ? scheme.secondary
                            : Colors.grey.shade600,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? scheme.secondary.withOpacity(0.1)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: scheme.secondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                Text(
                  durationStr,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isActive ? scheme.secondary : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
