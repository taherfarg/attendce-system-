import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:grouped_list/grouped_list.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../data/models/attendance_model.dart';
import '../../../../core/utils/time_utils.dart';

class HistoryTab extends StatelessWidget {
  final List<AttendanceModel> history;
  final bool isLoading;

  const HistoryTab({super.key, required this.history, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history_toggle_off,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No history records found',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Attendance History',
          style: TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: GroupedListView<AttendanceModel, DateTime>(
        elements: history,
        padding: const EdgeInsets.only(bottom: 100), // Space for FAB/Nav
        groupBy: (element) {
          final date = TimeUtils.toDubai(element.checkInTime);
          return DateTime(date.year, date.month, date.day);
        },
        groupSeparatorBuilder: (DateTime groupByValue) {
          final now = TimeUtils.nowDubai();
          String label;
          if (groupByValue.year == now.year &&
              groupByValue.month == now.month &&
              groupByValue.day == now.day) {
            label = 'Today';
          } else if (groupByValue.year == now.year &&
              groupByValue.month == now.month &&
              groupByValue.day == now.day - 1) {
            label = 'Yesterday';
          } else {
            label = DateFormat('MMMM d, y').format(groupByValue);
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: Colors.grey.shade500,
              ),
            ),
          );
        },
        itemBuilder: (context, element) {
          return _HistoryCard(
            item: element,
          ).animate().fade().slideY(begin: 0.1);
        },
        order: GroupedListOrder.DESC,
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final AttendanceModel item;

  const _HistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final checkIn = TimeUtils.toDubai(item.checkInTime);
    final checkOut = item.checkOutTime != null
        ? TimeUtils.toDubai(item.checkOutTime!)
        : null;
    final timeFormat = DateFormat('h:mm a');

    final bool isComplete = item.isComplete;
    final bool isByQr = item.verificationMethod == 'qr_code';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isComplete
                      ? Colors.blue.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isByQr ? Icons.qr_code_2 : Icons.face_rounded,
                  size: 20,
                  color: isComplete ? Colors.blue : Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isComplete ? 'Day Complete' : 'Active Session',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  if (item.totalMinutes > 0)
                    Text(
                      '${item.formattedDuration}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              if (item.isLate())
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'LATE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade400,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _TimeColumn(
                label: 'Checked In',
                time: timeFormat.format(checkIn),
                icon: Icons.login,
              ),
              if (checkOut != null)
                _TimeColumn(
                  label: 'Checked Out',
                  time: timeFormat.format(checkOut),
                  icon: Icons.logout,
                )
              else
                const _TimeColumn(
                  label: 'Status',
                  time: 'Working...',
                  icon: Icons.timer,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeColumn extends StatelessWidget {
  final String label;
  final String time;
  final IconData icon;

  const _TimeColumn({
    required this.label,
    required this.time,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: Colors.grey.shade400),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
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
