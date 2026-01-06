import 'package:flutter/material.dart';
import '../../../../data/models/attendance_model.dart';

class ProfileTab extends StatelessWidget {
  final String userName;
  final String userEmail; // We might need to pass this or fetch it
  final List<AttendanceModel> history;
  final VoidCallback onLogout;

  const ProfileTab({
    super.key,
    required this.userName,
    this.userEmail = '',
    required this.history,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate Lifetime Stats
    int totalMinutes = 0;
    int totalDays = 0;
    int lateDays = 0;

    // Use a Set to count unique days if multiple check-ins (though unlikely for this model)
    final Set<String> daysSet = {};

    for (var item in history) {
      totalMinutes += item.totalMinutes;
      // Simple day key
      final date = item.checkInTime.toIso8601String().split('T')[0];
      daysSet.add(date);

      if (item.isLate()) lateDays++;
    }
    totalDays = daysSet.length;
    final totalHours = totalMinutes ~/ 60;

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'My Profile',
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Avatar Section
            Center(
              child: Column(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: scheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    userName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  if (userEmail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      userEmail,
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Stats Grid
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Lifetime Statistics',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: 'Total Hours',
                          value: '$totalHours',
                          icon: Icons.access_time_filled,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _StatCard(
                          label: 'Days Worked',
                          value: '$totalDays',
                          icon: Icons.calendar_today,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: 'On Time',
                          value: '${totalDays - lateDays}',
                          icon: Icons.stars_rounded,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _StatCard(
                          label: 'Late Arrivals',
                          value: '$lateDays',
                          icon: Icons.directions_run_rounded,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Settings / Logout
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Notifications',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: Switch.adaptive(value: true, onChanged: (val) {}),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Dark Mode',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: Switch.adaptive(value: false, onChanged: (val) {}),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded, color: Colors.white),
                label: const Text(
                  'Log Out',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}
