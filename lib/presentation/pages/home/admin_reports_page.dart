import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _attendance = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    try {
      final response = await _client
          .from('attendance')
          .select('*, users(name)')
          .order('check_in_time', ascending: false)
          .limit(100);
      setState(() {
        _attendance = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String _formatDate(String? date) {
    if (date == null) return '-';
    return DateFormat('MMM d, h:mm a').format(DateTime.parse(date).toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Reports'),
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAttendance,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _attendance.length,
                itemBuilder: (context, index) {
                  final record = _attendance[index];
                  final userName = record['users']?['name'] ?? 'Unknown';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                userName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const Spacer(),
                              Chip(
                                label: Text(
                                  record['status'] ?? 'present',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor: Colors.green.shade100,
                                padding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.login,
                                size: 16,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 4),
                              Text(_formatDate(record['check_in_time'])),
                              const SizedBox(width: 16),
                              const Icon(
                                Icons.logout,
                                size: 16,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(_formatDate(record['check_out_time'])),
                            ],
                          ),
                          if (record['total_minutes'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Duration: ${record['total_minutes']} min',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
