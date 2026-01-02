import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/auth/auth_service.dart';
import 'admin_users_page.dart';
import 'admin_reports_page.dart';
import 'admin_settings_page.dart';
import 'admin_notifications_page.dart';
import '../profile/face_test_page.dart';
import '../../../core/utils/time_utils.dart';

/// Modern minimal admin dashboard
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
  List<Map<String, dynamic>> _liveActivity = [];
  bool _isLoading = true;

  String? _errorMessage;

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
      // Start of Dubai day
      final startOfDay = DateTime(today.year, today.month, today.day);
      // Convert to UTC for database query (Dubai is UTC+4)
      final startOfDayUtc = startOfDay.subtract(const Duration(hours: 4));

      // 1. Fetch Stats
      final checkInsResponse = await client
          .from('attendance')
          .select('id')
          .gte('check_in_time', startOfDayUtc.toIso8601String());
      _todayCheckIns = (checkInsResponse as List).length;

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

      // 2. Fetch Live Activity (Try simple fetch first if join fails)
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
        // Fallback: Fetch without join to at least show times
        final fallbackResponse = await client
            .from('attendance')
            .select()
            .gte('check_in_time', startOfDayUtc.toIso8601String())
            .order('check_in_time', ascending: false);

        if (mounted) {
          setState(() {
            _liveActivity = List<Map<String, dynamic>>.from(fallbackResponse);
            _errorMessage = "User details missing: $joinError";
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.background,
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
                              'Welcome, Admin',
                              style: textTheme.bodyLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Dashboard',
                              style: textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                                letterSpacing: -1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          // Show error if exists
                          if (_errorMessage != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(_errorMessage!)),
                            );
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminNotificationsPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.notifications_outlined),
                        style: IconButton.styleFrom(
                          backgroundColor: scheme.surface,
                          foregroundColor: scheme.onSurfaceVariant,
                          side: BorderSide(
                            color: scheme.outlineVariant.withOpacity(0.5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          _loadDashboardData();
                        },
                        icon: Icon(
                          Icons.refresh_rounded,
                          color: _errorMessage != null
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: scheme.surface,
                          foregroundColor: scheme.onSurfaceVariant,
                          side: BorderSide(
                            color: _errorMessage != null
                                ? scheme.error
                                : scheme.outlineVariant.withOpacity(0.5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _authService.signOut(),
                        icon: const Icon(Icons.logout_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: scheme.errorContainer,
                          foregroundColor: scheme.error,
                        ),
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
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: scheme.error, fontSize: 12),
                    ),
                  ),
                ),

              // Stats grid
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _isLoading && _todayCheckIns == 0
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                          ),
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                value: _todayCheckIns.toString(),
                                label: 'Check-ins',
                                icon: Icons.login_rounded,
                                color: scheme.secondary, // Teal
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                value: _totalEmployees.toString(),
                                label: 'Employees',
                                icon: Icons.people_rounded,
                                color: scheme.primary, // Slate
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                value: _activeNow.toString(),
                                label: 'Active',
                                icon: Icons.circle,
                                color: const Color(
                                  0xFFF59E0B,
                                ), // Amber (kept for status)
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),

              // Live Activity Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.live_tv_rounded,
                          color: scheme.error,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Live Activity',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
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
                          padding: const EdgeInsets.all(32),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: scheme.outlineVariant.withOpacity(0.5),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.history_toggle_off_rounded,
                                size: 48,
                                color: scheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _isLoading ? 'Loading...' : 'No activity today',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final record = _liveActivity[index];
                          final userData =
                              record['users'] as Map<String, dynamic>? ?? {};
                          final checkIn = TimeUtils.toDubai(
                            DateTime.parse(record['check_in_time']),
                          );
                          final checkOutStr = record['check_out_time'];
                          final checkOut = checkOutStr != null
                              ? TimeUtils.toDubai(DateTime.parse(checkOutStr))
                              : null;

                          // Calculate duration
                          final duration = checkOut != null
                              ? checkOut.difference(checkIn)
                              : TimeUtils.nowDubai().difference(checkIn);
                          final hours = duration.inHours;
                          final minutes = duration.inMinutes.remainder(60);
                          final durationStr = '${hours}h ${minutes}m';

                          final isActive = checkOut == null;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: scheme.outlineVariant.withOpacity(0.5),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: isActive
                                      ? scheme.secondary
                                      : scheme.surfaceVariant,
                                  foregroundColor: isActive
                                      ? Colors.white
                                      : scheme.onSurfaceVariant,
                                  child: Text(
                                    (userData['name'] ?? '?')[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        userData['name'] ?? 'Unknown Employee',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                      Text(
                                        userData['role']
                                                ?.toString()
                                                .toUpperCase() ??
                                            'EMPLOYEE',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? scheme.primary.withOpacity(0.05)
                                            : scheme.surfaceVariant,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isActive
                                            ? 'Working ($durationStr)'
                                            : 'Done ($durationStr)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isActive
                                              ? scheme.primary
                                              : scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'In: ${_formatTime(checkIn)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    if (checkOut != null)
                                      Text(
                                        'Out: ${_formatTime(checkOut)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }, childCount: _liveActivity.length),
                      ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),

              // Menu header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Management',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // Menu items
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _MenuItem(
                        icon: Icons.people_outline_rounded,
                        title: 'Users',
                        subtitle: 'Manage employees',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminUsersPage(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _MenuItem(
                        icon: Icons.analytics_outlined,
                        title: 'Reports',
                        subtitle: 'View attendance logs',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminReportsPage(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _MenuItem(
                        icon: Icons.settings_outlined,
                        title: 'Settings',
                        subtitle: 'Configure system',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminSettingsPage(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _MenuItem(
                        icon: Icons.face_retouching_natural,
                        title: 'Face Test',
                        subtitle: 'Debug face matching',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const FaceTestPage(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: -1,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.01),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: scheme.onSurfaceVariant, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: scheme.onSurfaceVariant.withOpacity(0.5),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
