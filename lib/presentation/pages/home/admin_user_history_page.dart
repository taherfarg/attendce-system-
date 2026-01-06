import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/utils/time_utils.dart';
import '../../../data/models/attendance_model.dart';

class AdminUserHistoryPage extends StatefulWidget {
  final String userId;
  final String userName;

  const AdminUserHistoryPage({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<AdminUserHistoryPage> createState() => _AdminUserHistoryPageState();
}

class _AdminUserHistoryPageState extends State<AdminUserHistoryPage> {
  final SupabaseClient _client = Supabase.instance.client;
  List<AttendanceModel> _history = [];
  bool _isLoading = true;

  // Stats
  int _totalHours = 0;
  int _daysPresent = 0;
  int _lates = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final response = await _client
          .from('attendance')
          .select('*')
          .eq('user_id', widget.userId)
          .order('check_in_time', ascending: false);

      final List<AttendanceModel> data = (response as List)
          .map((json) => AttendanceModel.fromJson(json))
          .toList();

      // Calculate stats
      int minutes = 0;
      int lates = 0;
      final Set<String> days = {};

      for (var record in data) {
        minutes += record.totalMinutes;
        if (record.isLate()) lates++;
        final date = record.checkInTime;
        days.add('${date.year}-${date.month}-${date.day}');
      }

      if (mounted) {
        setState(() {
          _history = data;
          _totalHours = minutes ~/ 60;
          _daysPresent = days.length;
          _lates = lates;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading user history: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              widget.userName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
            const Text(
              'Attendance History',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: const Color(0xFF1E293B),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: scheme.primary))
          : CustomScrollView(
              slivers: [
                // Summary Cards
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Total Hours',
                            value: '$_totalHours',
                            icon: Icons.timer_outlined,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            label: 'Days Present',
                            value: '$_daysPresent',
                            icon: Icons.calendar_today_rounded,
                            color: Colors.teal,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            label: 'Late',
                            value: '$_lates',
                            icon: Icons.access_time_filled_rounded,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ).animate().fade().slideY(begin: 0.1),
                  ),
                ),

                // History List
                if (_history.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history_toggle_off_rounded,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No attendance records',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final item = _history[index];
                        return _HistoryCard(item: item)
                            .animate()
                            .fade(delay: (50 * index).ms)
                            .slideX(begin: 0.05);
                      }, childCount: _history.length),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
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
    final dateStr = DateFormat('EEE, MMM d').format(checkIn);
    final timeFormat = DateFormat('h:mm a');

    final isPresent = item.isCheckedIn;
    final isLate = item.isLate();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isPresent
                  ? Colors.green.withOpacity(0.1)
                  : Colors.blue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                DateFormat('d').format(checkIn),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: isPresent ? Colors.green : Colors.blue.shade700,
                ),
              ),
            ),
          ),
          title: Text(
            dateStr,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: Row(
            children: [
              if (isLate) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LATE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                item.formattedDuration,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                timeFormat.format(checkIn),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                checkOut != null ? timeFormat.format(checkOut) : 'Active',
                style: TextStyle(
                  color: isPresent ? Colors.green : Colors.grey.shade500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  const Divider(),
                  const SizedBox(height: 8),
                  _DetailRow(
                    icon: Icons.fingerprint,
                    label: 'Method',
                    value: item.verificationMethod.toUpperCase().replaceAll(
                      '_',
                      ' ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (item.wifiSsid != null) ...[
                    _DetailRow(
                      icon: Icons.wifi,
                      label: 'WiFi',
                      value: item.wifiSsid!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (item.formattedAddress != null)
                    _DetailRow(
                      icon: Icons.place_outlined,
                      label: 'Location',
                      value: item.formattedAddress!,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade400),
        const SizedBox(width: 12),
        Text(
          '$label:',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    );
  }
}
