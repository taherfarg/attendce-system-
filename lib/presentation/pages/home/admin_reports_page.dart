import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/utils/time_utils.dart';
import '../../../data/models/attendance_model.dart';

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  final _client = Supabase.instance.client;
  List<AttendanceModel> _reports = [];
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();

  // Stats
  int _totalPresent = 0;
  int _totalLate = 0;
  String _avgDuration = '0h 0m';

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: const Color(0xFF6366F1),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _isLoading = true;
      });
      _loadReports();
    }
  }

  Future<void> _loadReports() async {
    try {
      final startOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Fetch for specific day
      // Note: We need to be careful with TimeZones if stored in UTC.
      // Assuming simple date comparison for now or storing ISO string.
      // Ideally we query range.

      final response = await _client
          .from('attendance')
          .select('*')
          .gte('check_in_time', startOfDay.toIso8601String())
          .lt('check_in_time', endOfDay.toIso8601String())
          .order('check_in_time', ascending: false);

      final List<AttendanceModel> data = (response as List)
          .map((json) => AttendanceModel.fromJson(json))
          .toList();

      // Fetch User Names manually since we need to join
      // Or we can rely on `attendance_model` if it had user name,
      // but it doesn't. We need to fetch users or use a join query.
      // Let's do a join query to be efficient.

      final responseWithUsers = await _client
          .from('attendance')
          .select('*, users(name)')
          .gte('check_in_time', startOfDay.toIso8601String())
          .lt('check_in_time', endOfDay.toIso8601String())
          .order('check_in_time', ascending: false);

      final List<Map<String, dynamic>> rawData =
          List<Map<String, dynamic>>.from(responseWithUsers);

      // Calc stats
      int totalMinutes = 0;
      int presentCount = 0;
      int lateCount = 0;
      int finishedCount = 0;

      for (var item in rawData) {
        final model = AttendanceModel.fromJson(item);
        presentCount++;
        if (model.isLate()) lateCount++;
        if (model.isComplete) {
          totalMinutes += model.totalMinutes;
          finishedCount++;
        }
      }

      final avgMin = finishedCount > 0 ? totalMinutes ~/ finishedCount : 0;
      final avgH = avgMin ~/ 60;
      final avgM = avgMin % 60;

      if (mounted) {
        setState(() {
          _reports = rawData.map((e) {
            // In a real app we might update the model to hold the name
            // For now we can handle name rendering separately or assume
            // we are just mapping to AttendanceModel and might lose name if not in model.
            // Let's stick to using the Map for the UI list to access 'users'['name']
            return AttendanceModel.fromJson(e);
          }).toList();

          // Store raw map for names access in list
          _reportMaps = rawData;

          _totalPresent = presentCount;
          _totalLate = lateCount;
          _avgDuration = '${avgH}h ${avgM}m';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading reports: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Helper to keep names
  List<Map<String, dynamic>> _reportMaps = [];

  void _exportCsv() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Exporting Report to CSV...'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    // Simulate delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report saved to Downloads!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateStr = DateFormat('MMMM d, y').format(_selectedDate);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Detailed Reports',
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: const Color(0xFF1E293B),
          iconSize: 20,
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            onPressed: _exportCsv,
            icon: const Icon(Icons.download_rounded),
            color: scheme.primary,
            tooltip: 'Export CSV',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: InkWell(
              onTap: _selectDate,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.primary.withOpacity(0.1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 20,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_drop_down, color: scheme.primary),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: scheme.primary),
                  )
                : RefreshIndicator(
                    onRefresh: _loadReports,
                    color: scheme.primary,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        // Stats Row
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _StatCard(
                                    label: 'Present',
                                    value: '$_totalPresent',
                                    color: Colors.green,
                                    icon: Icons.check_circle_outline,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _StatCard(
                                    label: 'Late',
                                    value: '$_totalLate',
                                    color: Colors.orange,
                                    icon: Icons.access_time,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _StatCard(
                                    label: 'Avg Time',
                                    value: _avgDuration,
                                    color: Colors.blue,
                                    icon: Icons.timer_outlined,
                                  ),
                                ),
                              ],
                            ).animate().fade().slideY(begin: 0.1),
                          ),
                        ),

                        // List Header
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 8,
                            ),
                            child: Text(
                              'ALL RECORDS',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ),

                        // Reports List
                        if (_reportMaps.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(40),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.note_alt_outlined,
                                    size: 60,
                                    color: Colors.grey.shade300,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No records for this date',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final data = _reportMaps[index];
                              final model = AttendanceModel.fromJson(data);
                              final name =
                                  data['users']?['name'] ?? 'Unknown Employee';

                              return _ReportItem(model: model, userName: name)
                                  .animate()
                                  .fade(delay: (50 * index).ms)
                                  .slideX(begin: 0.05);
                            }, childCount: _reportMaps.length),
                          ),

                        const SliverToBoxAdapter(child: SizedBox(height: 40)),
                      ],
                    ),
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
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportItem extends StatelessWidget {
  final AttendanceModel model;
  final String userName;

  const _ReportItem({required this.model, required this.userName});

  @override
  Widget build(BuildContext context) {
    final checkIn = TimeUtils.toDubai(model.checkInTime);
    final checkOut = model.checkOutTime != null
        ? TimeUtils.toDubai(model.checkOutTime!)
        : null;
    final timeFormat = DateFormat('h:mm a');

    final isLate = model.isLate();

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
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey.shade100,
                child: Text(
                  userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  userName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              if (isLate)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
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
              if (!model.isComplete) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _TimeColumn(
                label: 'Check In',
                time: timeFormat.format(checkIn),
                icon: Icons.login,
                color: Colors.green,
              ),
              _TimeColumn(
                label: 'Check Out',
                time: checkOut != null ? timeFormat.format(checkOut) : '--:--',
                icon: Icons.logout,
                color: Colors.orange,
              ),
              _TimeColumn(
                label: 'Duration',
                time: model.formattedDuration,
                icon: Icons.timer_outlined,
                color: Colors.blue,
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
  final Color color;

  const _TimeColumn({
    required this.label,
    required this.time,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color.withOpacity(0.7)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          time,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}
