import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../data/models/attendance_model.dart';
import '../../../../core/utils/time_utils.dart';
import 'dart:ui';

class DashboardTab extends StatelessWidget {
  final String userName;
  final bool isCheckedIn;
  final bool isComplete;
  final Duration elapsedTime;
  final AttendanceModel? todayRecord;
  final int weeklyMinutes;
  final int daysPresent;
  final List<bool> weekDays;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;
  final bool isLoading;

  const DashboardTab({
    super.key,
    required this.userName,
    required this.isCheckedIn,
    required this.isComplete,
    required this.elapsedTime,
    required this.todayRecord,
    required this.weeklyMinutes,
    required this.daysPresent,
    required this.weekDays,
    required this.onCheckIn,
    required this.onCheckOut,
    this.isLoading = false,
  });

  String _getGreeting() {
    final hour = TimeUtils.nowDubai().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours);
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getGreeting(),
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ).animate().fade().slideX(begin: -0.1),
                Text(
                  userName.isNotEmpty ? userName : 'Employee',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ).animate().fade(delay: 100.ms).slideX(begin: -0.1),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _LiveProgressTimer(
              elapsedTime: elapsedTime,
              isCheckedIn: isCheckedIn,
              isComplete: isComplete,
              formattedTime: _formatDuration(elapsedTime),
              todayRecord: todayRecord,
            ).animate().scale(delay: 200.ms, duration: 400.ms),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Check In',
                    icon: Icons.login,
                    color: const Color(0xFF10B981),
                    isEnabled: !isCheckedIn && !isComplete,
                    onTap: onCheckIn,
                  ).animate().fade(delay: 300.ms).slideY(begin: 0.2),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _ActionButton(
                    label: 'Check Out',
                    icon: Icons.logout,
                    color: const Color(0xFFF59E0B),
                    isEnabled: isCheckedIn,
                    onTap: onCheckOut,
                  ).animate().fade(delay: 400.ms).slideY(begin: 0.2),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _WeeklySummary(
              weekDays: weekDays,
              totalMinutes: weeklyMinutes,
              daysPresent: daysPresent,
            ).animate().fade(delay: 500.ms).slideY(begin: 0.1),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

class _LiveProgressTimer extends StatelessWidget {
  final Duration elapsedTime;
  final bool isCheckedIn;
  final bool isComplete;
  final String formattedTime;
  final AttendanceModel? todayRecord;

  const _LiveProgressTimer({
    required this.elapsedTime,
    required this.isCheckedIn,
    required this.isComplete,
    required this.formattedTime,
    this.todayRecord,
  });

  @override
  Widget build(BuildContext context) {
    // 8 hours goal
    final double progress = (elapsedTime.inSeconds / (8 * 3600)).clamp(
      0.0,
      1.0,
    );
    final Color progressColor = isCheckedIn
        ? const Color(0xFF6366F1)
        : Colors.grey.shade300;

    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 220,
            width: 220,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 15,
                  color: Colors.grey.shade100,
                  strokeCap: StrokeCap.round,
                ),
                CircularProgressIndicator(
                  value: isComplete ? 1.0 : progress,
                  strokeWidth: 15,
                  color: isComplete ? Colors.green : const Color(0xFF6366F1),
                  strokeCap: StrokeCap.round,
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isComplete
                          ? Icons.check_circle
                          : isCheckedIn
                          ? Icons.timer
                          : Icons.timer_off_outlined,
                      size: 32,
                      color: isComplete
                          ? Colors.green
                          : isCheckedIn
                          ? const Color(0xFF6366F1)
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isComplete
                          ? '${(todayRecord?.totalMinutes ?? 0) ~/ 60}h ${(todayRecord?.totalMinutes ?? 0) % 60}m'
                          : formattedTime,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        fontFeatures: [FontFeature.tabularFigures()],
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isComplete
                          ? 'Completed'
                          : isCheckedIn
                          ? 'Working'
                          : 'Ready',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade500,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (todayRecord != null) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _TimeInfo(
                  label: 'Start',
                  time: DateFormat(
                    'h:mm a',
                  ).format(TimeUtils.toDubai(todayRecord!.checkInTime)),
                  icon: Icons.login,
                ),
                _TimeInfo(
                  label: 'End',
                  time: todayRecord!.checkOutTime != null
                      ? DateFormat(
                          'h:mm a',
                        ).format(TimeUtils.toDubai(todayRecord!.checkOutTime!))
                      : '--:--',
                  icon: Icons.logout,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TimeInfo extends StatelessWidget {
  final String label;
  final String time;
  final IconData icon;

  const _TimeInfo({
    required this.label,
    required this.time,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.grey.shade400),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          time,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isEnabled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.isEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isEnabled ? color : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 28,
                color: isEnabled ? Colors.white : Colors.grey.shade400,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isEnabled ? Colors.white : Colors.grey.shade400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This Week',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (index) {
              final active = weekDays[index];
              return Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFF6366F1)
                          : Colors.grey.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        days[index],
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: active ? Colors.white : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _StatBadge(
                icon: Icons.access_time_filled,
                value: '${totalMinutes ~/ 60}h ${totalMinutes % 60}m',
                label: 'Total Hours',
                color: Colors.orange,
                bgColor: Colors.orange.shade50,
              ),
              const SizedBox(width: 12),
              _StatBadge(
                icon: Icons.calendar_today,
                value: '$daysPresent Days',
                label: 'Attendance',
                color: Colors.blue,
                bgColor: Colors.blue.shade50,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final Color bgColor;

  const _StatBadge({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: color.withOpacity(0.8)),
            ),
          ],
        ),
      ),
    );
  }
}
