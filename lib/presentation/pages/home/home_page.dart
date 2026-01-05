import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/services/offline_queue.dart';
import '../attendance/face_scan_page.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/models/attendance_model.dart';
import '../../../core/utils/time_utils.dart';
import '../../common_widgets/shimmer_loading.dart';

/// Modern employee dashboard with live timer and weekly stats
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _authService = AuthService();
  final _repo = AttendanceRepository();
  final _offlineQueue = OfflineQueueService();

  List<AttendanceModel> _history = [];
  bool _isLoading = true;
  int _pendingCount = 0;
  AttendanceModel? _todayRecord;
  String _userName = '';

  // Weekly stats
  int _weeklyMinutes = 0;
  int _daysPresent = 0;
  List<bool> _weekDays = List.filled(7, false); // Mon-Sun

  // Live timer
  Timer? _liveTimer;
  Duration _elapsedTime = Duration.zero;

  final _timeFormat = DateFormat('HH:mm');
  final _dateFormat = DateFormat('EEE, MMM d');

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
      // Load user name
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        final userData = await Supabase.instance.client
            .from('users')
            .select('name')
            .eq('id', userId)
            .maybeSingle();
        _userName = userData?['name'] ?? 'Employee';
      }

      final data = await _repo.getHistory();
      final pending = await _offlineQueue.getPendingCount();

      final now = TimeUtils.nowDubai();

      // Get start of current week (Monday)
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final startOfWeek = DateTime(
        weekStart.year,
        weekStart.month,
        weekStart.day,
      );

      // Calculate weekly stats
      int weeklyMinutes = 0;
      Set<int> presentDays = {};
      List<bool> weekDays = List.filled(7, false);

      for (var record in data) {
        final checkIn = TimeUtils.toDubai(record.checkInTime);
        if (checkIn.isAfter(startOfWeek)) {
          weeklyMinutes += record.totalMinutes;
          final dayIndex = checkIn.weekday - 1; // Mon=0, Sun=6
          if (dayIndex >= 0 && dayIndex < 7) {
            weekDays[dayIndex] = true;
            presentDays.add(checkIn.day);
          }
        }
      }

      // Find today's records
      final todayRecords = data.where((r) {
        final checkIn = TimeUtils.toDubai(r.checkInTime);
        return checkIn.year == now.year &&
            checkIn.month == now.month &&
            checkIn.day == now.day;
      }).toList();

      // Determine "Today's Status"
      AttendanceModel? statusRecord;
      try {
        statusRecord = todayRecords.firstWhere((r) => r.checkOutTime == null);
      } catch (_) {
        if (todayRecords.isNotEmpty) {
          statusRecord = todayRecords.first;
        }
      }

      if (mounted) {
        setState(() {
          _history = data;
          _pendingCount = pending;
          _todayRecord = statusRecord;
          _weeklyMinutes = weeklyMinutes;
          _daysPresent = presentDays.length;
          _weekDays = weekDays;
          _isLoading = false;
        });

        // Start live timer if checked in
        _startLiveTimer();
      }
    } catch (e) {
      debugPrint("Error loading data: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startLiveTimer() {
    _liveTimer?.cancel();

    if (_todayRecord != null && _todayRecord!.isCheckedIn) {
      // Calculate initial elapsed time
      final checkIn = TimeUtils.toDubai(_todayRecord!.checkInTime);
      final now = TimeUtils.nowDubai();
      _elapsedTime = now.difference(checkIn);

      // Update every second
      _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _elapsedTime += const Duration(seconds: 1);
          });
        }
      });
    }
  }

  String _formatElapsedTime(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
    }
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
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

  String _getGreeting() {
    final hour = TimeUtils.nowDubai().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCheckedIn = _todayRecord?.isCheckedIn ?? false;
    final isComplete = _todayRecord?.isComplete ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: scheme.primary,
          child: _isLoading
              ? const ShimmerList(itemCount: 6, height: 90)
              : CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // Header with greeting
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getGreeting(),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ).animate().fade().slideX(begin: -0.2),
                                  const SizedBox(height: 4),
                                  Text(
                                        _userName.isNotEmpty
                                            ? _userName
                                            : 'Dashboard',
                                        style: const TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1E293B),
                                        ),
                                      )
                                      .animate()
                                      .fade(delay: 100.ms)
                                      .slideX(begin: -0.2),
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
                              ).animate().scale(),
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

                    // Live Status Card
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _LiveStatusCard(
                          isCheckedIn: isCheckedIn,
                          isComplete: isComplete,
                          elapsedTime: _elapsedTime,
                          todayRecord: _todayRecord,
                          timeFormat: _timeFormat,
                          formatElapsedTime: _formatElapsedTime,
                        ).animate().fade(duration: 400.ms).slideY(begin: 0.05),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),

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
                                isEnabled: !isCheckedIn,
                                isPrimary: true,
                                onTap: _goCheckIn,
                              ).animate().fade(delay: 200.ms).scale(),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _ActionButton(
                                icon: Icons.logout_rounded,
                                label: 'Check Out',
                                isEnabled: isCheckedIn,
                                isPrimary: false,
                                onTap: _goCheckOut,
                              ).animate().fade(delay: 300.ms).scale(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),

                    // Weekly Summary
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _WeeklySummary(
                          weekDays: _weekDays,
                          totalMinutes: _weeklyMinutes,
                          daysPresent: _daysPresent,
                        ).animate().fade(delay: 350.ms).slideY(begin: 0.05),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),

                    // History header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Text(
                              'Recent Activity',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${_history.length} records',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
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
                        ).animate().fade(delay: 400.ms),
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
                                )
                                .animate()
                                .fade(duration: 300.ms, delay: (50 * index).ms)
                                .slideX(begin: 0.05);
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
}

// Live Status Card with gradient and timer
class _LiveStatusCard extends StatelessWidget {
  final bool isCheckedIn;
  final bool isComplete;
  final Duration elapsedTime;
  final AttendanceModel? todayRecord;
  final DateFormat timeFormat;
  final String Function(Duration) formatElapsedTime;

  const _LiveStatusCard({
    required this.isCheckedIn,
    required this.isComplete,
    required this.elapsedTime,
    required this.todayRecord,
    required this.timeFormat,
    required this.formatElapsedTime,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    List<Color> gradientColors;
    String status;
    IconData icon;
    String timerText;

    if (isCheckedIn) {
      gradientColors = [const Color(0xFF0F172A), const Color(0xFF1E3A5F)];
      status = 'Currently Working';
      icon = Icons.timer_outlined;
      timerText = formatElapsedTime(elapsedTime);
    } else if (isComplete) {
      gradientColors = [const Color(0xFF0D9488), const Color(0xFF14B8A6)];
      status = 'Day Complete';
      icon = Icons.check_circle_outlined;
      timerText = todayRecord != null
          ? '${todayRecord!.totalMinutes ~/ 60}h ${todayRecord!.totalMinutes % 60}m'
          : '0h 0m';
    } else {
      gradientColors = [Colors.grey.shade300, Colors.grey.shade400];
      status = 'Not Checked In';
      icon = Icons.schedule;
      timerText = '--:--';
    }

    DateTime? checkInTime;
    DateTime? checkOutTime;
    if (todayRecord != null) {
      checkInTime = TimeUtils.toDubai(todayRecord!.checkInTime);
      if (todayRecord!.checkOutTime != null) {
        checkOutTime = TimeUtils.toDubai(todayRecord!.checkOutTime!);
      }
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today\'s Status',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (isCheckedIn)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade400,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          // Timer display
          Center(
            child: Text(
              timerText,
              style: const TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -1,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Check-in/out times
          if (checkInTime != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TimeChip(label: 'In', time: timeFormat.format(checkInTime)),
                if (checkOutTime != null) ...[
                  const SizedBox(width: 16),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white.withOpacity(0.5),
                    size: 16,
                  ),
                  const SizedBox(width: 16),
                  _TimeChip(
                    label: 'Out',
                    time: timeFormat.format(checkOutTime),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String label;
  final String time;

  const _TimeChip({required this.label, required this.time});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          Text(
            time,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// Weekly Summary Widget
class _WeeklySummary extends StatelessWidget {
  final List<bool> weekDays;
  final int totalMinutes;
  final int daysPresent;

  const _WeeklySummary({
    required this.weekDays,
    required this.totalMinutes,
    required this.daysPresent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final avgMinutes = daysPresent > 0 ? totalMinutes ~/ daysPresent : 0;
    final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              const Text(
                'This Week',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Week dots
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(7, (index) {
              final isPresent = weekDays[index];
              return Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isPresent
                          ? scheme.secondary
                          : Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: isPresent
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    days[index],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isPresent
                          ? scheme.secondary
                          : Colors.grey.shade400,
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 20),
          // Stats row
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  label: 'Total Hours',
                  value: '${totalMinutes ~/ 60}h ${totalMinutes % 60}m',
                  icon: Icons.access_time_filled,
                  color: scheme.primary,
                ),
              ),
              Container(width: 1, height: 40, color: Colors.grey.shade200),
              Expanded(
                child: _StatItem(
                  label: 'Avg/Day',
                  value: '${avgMinutes ~/ 60}h ${avgMinutes % 60}m',
                  icon: Icons.trending_up_rounded,
                  color: scheme.secondary,
                ),
              ),
              Container(width: 1, height: 40, color: Colors.grey.shade200),
              Expanded(
                child: _StatItem(
                  label: 'Days',
                  value: '$daysPresent',
                  icon: Icons.event_available_rounded,
                  color: const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

// Action Button
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
    final color = isPrimary ? scheme.primary : scheme.secondary;

    return Material(
      color: isEnabled ? color : scheme.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: isEnabled ? 4 : 0,
      shadowColor: color.withOpacity(0.3),
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: isEnabled ? null : Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 24,
                color: isEnabled
                    ? Colors.white
                    : scheme.onSurfaceVariant.withOpacity(0.5),
              ),
              const SizedBox(width: 8),
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

// History Item
class _HistoryItem extends StatelessWidget {
  final AttendanceModel item;
  final DateFormat timeFormat;
  final DateFormat dateFormat;

  const _HistoryItem({
    required this.item,
    required this.timeFormat,
    required this.dateFormat,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final checkIn = TimeUtils.toDubai(item.checkInTime);
    final checkOut = item.checkOutTime != null
        ? TimeUtils.toDubai(item.checkOutTime!)
        : null;
    final isComplete = item.isComplete;
    final minutes = item.totalMinutes;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isComplete
                  ? scheme.secondary.withOpacity(0.1)
                  : scheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isComplete
                  ? Icons.check_circle_rounded
                  : Icons.access_time_filled,
              size: 22,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${minutes ~/ 60}h ${minutes % 60}m',
                style: TextStyle(
                  fontSize: 13,
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
