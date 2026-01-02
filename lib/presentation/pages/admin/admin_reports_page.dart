import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

/// Admin page for viewing attendance reports and analytics
class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  List<Map<String, dynamic>> _attendanceRecords = [];
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  String? _selectedUserId;

  final _dateFormat = DateFormat('MMM dd, yyyy');
  final _timeFormat = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final client = Supabase.instance.client;

      // Load users for filter dropdown
      final usersResponse = await client
          .from('users')
          .select('id, name')
          .eq('role', 'employee');
      _users = List<Map<String, dynamic>>.from(usersResponse);

      // Load attendance records
      await _loadAttendance();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadAttendance() async {
    try {
      final client = Supabase.instance.client;

      var query = client
          .from('attendance')
          .select('''
        id,
        user_id,
        check_in_time,
        check_out_time,
        status,
        total_minutes,
        wifi_ssid,
        users(name)
      ''')
          .gte('check_in_time', _startDate.toIso8601String())
          .lte(
            'check_in_time',
            _endDate.add(const Duration(days: 1)).toIso8601String(),
          );

      if (_selectedUserId != null) {
        query = query.eq('user_id', _selectedUserId!);
      }

      final response = await query.order('check_in_time', ascending: false);

      if (mounted) {
        setState(() {
          _attendanceRecords = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Load attendance error: $e');
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadAttendance();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Calculate summary stats
    final totalRecords = _attendanceRecords.length;
    final totalMinutes = _attendanceRecords.fold<int>(
      0,
      (sum, r) => sum + ((r['total_minutes'] ?? 0) as int),
    );
    final avgMinutes = totalRecords > 0 ? totalMinutes ~/ totalRecords : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Reports'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filters
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[100],
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _selectDateRange,
                              icon: const Icon(Icons.date_range),
                              label: Text(
                                '${_dateFormat.format(_startDate)} - ${_dateFormat.format(_endDate)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              value: _selectedUserId,
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              hint: const Text('All Users'),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('All Users'),
                                ),
                                ..._users.map(
                                  (u) => DropdownMenuItem(
                                    value: u['id'] as String,
                                    child: Text(u['name'] as String),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() => _selectedUserId = value);
                                _loadAttendance();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Summary stats
                      Row(
                        children: [
                          _SummaryChip(
                            icon: Icons.list,
                            label: 'Records',
                            value: totalRecords.toString(),
                          ),
                          const SizedBox(width: 12),
                          _SummaryChip(
                            icon: Icons.timer,
                            label: 'Total Hours',
                            value: (totalMinutes / 60).toStringAsFixed(1),
                          ),
                          const SizedBox(width: 12),
                          _SummaryChip(
                            icon: Icons.analytics,
                            label: 'Avg/Day',
                            value: '${(avgMinutes / 60).toStringAsFixed(1)}h',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Records list
                Expanded(
                  child: _attendanceRecords.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('No records found'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _attendanceRecords.length,
                          itemBuilder: (context, index) {
                            final record = _attendanceRecords[index];
                            final checkIn = DateTime.parse(
                              record['check_in_time'],
                            );
                            final checkOut = record['check_out_time'] != null
                                ? DateTime.parse(record['check_out_time'])
                                : null;
                            final userName =
                                (record['users'] as Map?)?['name'] ?? 'Unknown';
                            final totalMin = record['total_minutes'] ?? 0;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: Colors.blue,
                                          radius: 18,
                                          child: Text(
                                            userName[0].toUpperCase(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                userName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                _dateFormat.format(checkIn),
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(
                                              record['status'],
                                            ).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          child: Text(
                                            record['status']?.toUpperCase() ??
                                                'N/A',
                                            style: TextStyle(
                                              color: _getStatusColor(
                                                record['status'],
                                              ),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    const Divider(height: 1),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        _TimeBlock(
                                          icon: Icons.login,
                                          label: 'Check In',
                                          time: _timeFormat.format(checkIn),
                                          color: Colors.green,
                                        ),
                                        const SizedBox(width: 24),
                                        _TimeBlock(
                                          icon: Icons.logout,
                                          label: 'Check Out',
                                          time: checkOut != null
                                              ? _timeFormat.format(checkOut)
                                              : '--:--',
                                          color: Colors.orange,
                                        ),
                                        const Spacer(),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            const Text(
                                              'Duration',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            Text(
                                              '${(totalMin / 60).toStringAsFixed(1)}h',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.indigo,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (record['wifi_ssid'] != null) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.wifi,
                                            size: 14,
                                            color: Colors.grey[400],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            record['wifi_ssid'],
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[500],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'present':
        return Colors.green;
      case 'late':
        return Colors.orange;
      case 'absent':
        return Colors.red;
      case 'early_out':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.indigo),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  final IconData icon;
  final String label;
  final String time;
  final Color color;

  const _TimeBlock({
    required this.icon,
    required this.label,
    required this.time,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            Text(
              time,
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ],
    );
  }
}
