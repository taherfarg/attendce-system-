import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  final _client = Supabase.instance.client;
  Map<String, dynamic> _settings = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final response = await _client.from('system_settings').select('*');
      final settings = <String, dynamic>{};
      for (final s in response) {
        settings[s['setting_key']] = s['setting_value'];
      }
      setState(() {
        _settings = settings;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSettings,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSettingCard(
                    'Office Location',
                    Icons.location_on,
                    _settings['office_location']?.toString() ?? 'Not set',
                  ),
                  _buildSettingCard(
                    'Allowed Radius',
                    Icons.circle_outlined,
                    '${_settings['allowed_radius_meters'] ?? 100} meters',
                  ),
                  _buildSettingCard(
                    'Allowed WiFi',
                    Icons.wifi,
                    _settings['wifi_allowlist']?.toString() ?? 'Not set',
                  ),
                  _buildSettingCard(
                    'Working Hours',
                    Icons.access_time,
                    _settings['working_hours']?.toString() ?? '09:00 - 18:00',
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSettingCard(String title, IconData icon, String value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF6366F1)),
        ),
        title: Text(title),
        subtitle: Text(
          value,
          style: const TextStyle(fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
