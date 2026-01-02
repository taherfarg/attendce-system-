import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/services/offline_queue.dart';
import '../attendance/face_scan_page.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../core/utils/time_utils.dart';

/// Modern minimal employee home page
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _authService = AuthService();
  final _repo = AttendanceRepository();
  final _offlineQueue = OfflineQueueService();

  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  int _pendingCount = 0;
  Map<String, dynamic>? _todayRecord;

  final _timeFormat = DateFormat('HH:mm');
  final _dateFormat = DateFormat('EEE, MMM d');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final data = await _repo.getHistory();
      final pending = await _offlineQueue.getPendingCount();

      final now = TimeUtils.nowDubai();

      // logic: Find today's records
      final todayRecords = data
          .where((r) {
            if (r == null) return false;
            final checkIn = TimeUtils.toDubai(
              DateTime.parse(r['check_in_time']),
            );
            return checkIn.year == now.year &&
                checkIn.month == now.month &&
                checkIn.day == now.day;
          })
          .cast<Map<String, dynamic>>()
          .toList();

      // logic: Determine "Today's Status"
      // Priority 1: Currently Active (check_out is null)
      // Priority 2: Latest completed
      Map<String, dynamic>? statusRecord;
      try {
        statusRecord = todayRecords.firstWhere(
          (r) => r['check_out_time'] == null,
        );
      } catch (_) {
        // No active record, take the first one (latest) if exists
        if (todayRecords.isNotEmpty) {
          statusRecord = todayRecords.first;
        }
      }

      if (mounted) {
        setState(() {
          _history = data;
          _pendingCount = pending;
          _todayRecord = statusRecord;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _goCheckIn() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FaceScanPage(isCheckIn: true)),
    ).then((_) => _loadData());
  }

  void _goCheckOut() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FaceScanPage(isCheckIn: false)),
    ).then((_) => _loadData());
  }

  @override
  Widget build(BuildContext context) {
    final isCheckedIn =
        _todayRecord != null && _todayRecord!['check_out_time'] == null;
    final isComplete =
        _todayRecord != null && _todayRecord!['check_out_time'] != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : CustomScrollView(
                  slivers: [
                    // App bar
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Good ${_getGreeting()}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Dashboard',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_pendingCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.cloud_off_rounded,
                                      size: 16,
                                      color: Colors.orange.shade700,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$_pendingCount',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => _authService.signOut(),
                              icon: const Icon(Icons.logout_rounded),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Status card
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _StatusCard(
                          isCheckedIn: isCheckedIn,
                          isComplete: isComplete,
                          todayRecord: _todayRecord,
                          timeFormat: _timeFormat,
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),

                    // Action buttons
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: _ActionButton(
                                icon: Icons.login_rounded,
                                label: 'Check In',
                                isEnabled:
                                    !isCheckedIn, // Allow check-in as long as not currently checked in
                                isPrimary: true,
                                onTap: _goCheckIn,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _ActionButton(
                                icon: Icons.logout_rounded,
                                label: 'Check Out',
                                isEnabled: isCheckedIn,
                                isPrimary: false,
                                onTap: _goCheckOut,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),

                    // History header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'Recent Activity',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),

                    // History list
                    if (_history.isEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          padding: const EdgeInsets.all(40),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.history_rounded,
                                size: 48,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No records yet',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index >= _history.length || index >= 7)
                              return null;
                            final item = _history[index];
                            return _HistoryItem(
                              item: item,
                              timeFormat: _timeFormat,
                              dateFormat: _dateFormat,
                            );
                          },
                          childCount: _history.length > 7 ? 7 : _history.length,
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
                ),
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }
}

class _StatusCard extends StatelessWidget {
  final bool isCheckedIn;
  final bool isComplete;
  final Map<String, dynamic>? todayRecord;
  final DateFormat timeFormat;

  const _StatusCard({
    required this.isCheckedIn,
    required this.isComplete,
    required this.todayRecord,
    required this.timeFormat,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Color bgColor;
    Color textColor;
    String status;
    IconData icon;

    if (isCheckedIn) {
      bgColor = scheme.primary; // Slate-900 (Active)
      textColor = Colors.white;
      status = 'Working';
      icon = Icons.timer_outlined;
    } else if (isComplete) {
      bgColor = scheme.secondary; // Teal (Complete)
      textColor = Colors.white;
      status = 'Day Complete';
      icon = Icons.check_circle_outlined;
    } else {
      bgColor = Colors.white;
      textColor = scheme.onSurfaceVariant; // Slate-500
      status = 'Not Checked In';
      icon = Icons.schedule;
    }

    // Parse times to Local (DUBAI)
    DateTime? checkInTime;
    DateTime? checkOutTime;
    if (todayRecord != null) {
      checkInTime = TimeUtils.toDubai(
        DateTime.parse(todayRecord!['check_in_time']),
      );
      if (todayRecord!['check_out_time'] != null) {
        checkOutTime = TimeUtils.toDubai(
          DateTime.parse(todayRecord!['check_out_time']),
        );
      }
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: isCheckedIn || isComplete
            ? null
            : Border.all(color: scheme.outlineVariant),
        boxShadow: isCheckedIn || isComplete
            ? [
                BoxShadow(
                  color: bgColor.withOpacity(0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: textColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: textColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Today\'s Status',
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor.withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    letterSpacing: -0.5,
                  ),
                ),
                if (checkInTime != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'In: ${timeFormat.format(checkInTime)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: textColor.withOpacity(0.9),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (checkOutTime != null) ...[
                        Text(
                          '  •  ',
                          style: TextStyle(color: textColor.withOpacity(0.5)),
                        ),
                        Text(
                          'Out: ${timeFormat.format(checkOutTime)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: textColor.withOpacity(0.9),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isEnabled;
  final bool isPrimary;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isEnabled,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isPrimary
        ? scheme.primary
        : scheme.secondary; // Slate or Teal

    return Material(
      color: isEnabled ? color : scheme.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: isEnabled ? 4 : 0,
      shadowColor: color.withOpacity(0.2),
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: isEnabled ? null : Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 32,
                color: isEnabled
                    ? Colors.white
                    : scheme.onSurfaceVariant.withOpacity(0.5),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isEnabled
                      ? Colors.white
                      : scheme.onSurfaceVariant.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final Map<String, dynamic> item;
  final DateFormat timeFormat;
  final DateFormat dateFormat;

  const _HistoryItem({
    required this.item,
    required this.timeFormat,
    required this.dateFormat,
  });

  String _formatDuration(int minutes) {
    if (minutes == 0) return '0m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // IMPORTANT: Parse to Dubai Time for Display!
    final checkIn = TimeUtils.toDubai(DateTime.parse(item['check_in_time']));
    final checkOut = item['check_out_time'] != null
        ? TimeUtils.toDubai(DateTime.parse(item['check_out_time']))
        : null;

    final isComplete = checkOut != null;
    final minutes = item['total_minutes'] ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isComplete
                  ? scheme.secondary.withOpacity(0.1)
                  : scheme.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isComplete ? Icons.check : Icons.access_time_filled,
              size: 20,
              color: isComplete ? scheme.secondary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateFormat.format(checkIn),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${timeFormat.format(checkIn)} - ${checkOut != null ? timeFormat.format(checkOut) : 'In progress'}',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (isComplete)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _formatDuration(minutes),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: scheme.secondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
