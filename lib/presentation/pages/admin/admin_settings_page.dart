import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin page for configuring system settings
class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;

  // Settings values
  double _officeLat = 25.2048;
  double _officeLng = 55.2708;
  int _allowedRadius = 100;
  List<String> _wifiAllowlist = [];

  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _radiusController = TextEditingController();
  final _newWifiController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    _radiusController.dispose();
    _newWifiController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('system_settings')
          .select('setting_key, setting_value');

      final settings = Map.fromIterable(
        response as List,
        key: (s) => s['setting_key'],
        value: (s) => s['setting_value'],
      );

      // Parse office location
      if (settings['office_location'] != null) {
        final loc = settings['office_location'];
        _officeLat = (loc['lat'] as num).toDouble();
        _officeLng = (loc['lng'] as num).toDouble();
      }

      // Parse radius
      if (settings['allowed_radius_meters'] != null) {
        _allowedRadius =
            int.tryParse(settings['allowed_radius_meters'].toString()) ?? 100;
      }

      // Parse WiFi list
      if (settings['wifi_allowlist'] != null) {
        _wifiAllowlist = List<String>.from(settings['wifi_allowlist']);
      }

      _latController.text = _officeLat.toString();
      _lngController.text = _officeLng.toString();
      _radiusController.text = _allowedRadius.toString();

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading settings: $e')));
      }
    }
  }

  Future<void> _saveSetting(
    String key,
    dynamic value, {
    String? description,
  }) async {
    final client = Supabase.instance.client;

    await client.from('system_settings').upsert({
      'setting_key': key,
      'setting_value': value,
      'description': description,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'setting_key');
  }

  Future<void> _saveAllSettings() async {
    setState(() => _isSaving = true);

    try {
      // Validate inputs
      final lat = double.tryParse(_latController.text);
      final lng = double.tryParse(_lngController.text);
      final radius = int.tryParse(_radiusController.text);

      if (lat == null || lat < -90 || lat > 90) {
        throw 'Invalid latitude (must be -90 to 90)';
      }
      if (lng == null || lng < -180 || lng > 180) {
        throw 'Invalid longitude (must be -180 to 180)';
      }
      if (radius == null || radius < 10 || radius > 10000) {
        throw 'Invalid radius (must be 10 to 10000 meters)';
      }

      // Save all settings
      await _saveSetting('office_location', {
        'lat': lat,
        'lng': lng,
      }, description: 'Office GPS coordinates');

      await _saveSetting(
        'allowed_radius_meters',
        radius.toString(),
        description: 'Maximum allowed distance from office in meters',
      );

      await _saveSetting(
        'wifi_allowlist',
        _wifiAllowlist,
        description: 'List of authorized WiFi SSIDs',
      );

      _officeLat = lat;
      _officeLng = lng;
      _allowedRadius = radius;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }

    if (mounted) setState(() => _isSaving = false);
  }

  void _addWifi() {
    final ssid = _newWifiController.text.trim();
    if (ssid.isEmpty) return;

    if (_wifiAllowlist.contains(ssid)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('WiFi already in list')));
      return;
    }

    setState(() {
      _wifiAllowlist.add(ssid);
      _newWifiController.clear();
    });
  }

  void _removeWifi(String ssid) {
    setState(() {
      _wifiAllowlist.remove(ssid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Settings'),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveAllSettings,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Office Location Section
                  _SectionHeader(
                    icon: Icons.location_on,
                    title: 'Office Location',
                    subtitle: 'GPS coordinates of the office',
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _latController,
                                  decoration: const InputDecoration(
                                    labelText: 'Latitude',
                                    hintText: '25.2048',
                                    prefixIcon: Icon(Icons.north),
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _lngController,
                                  decoration: const InputDecoration(
                                    labelText: 'Longitude',
                                    hintText: '55.2708',
                                    prefixIcon: Icon(Icons.east),
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tip: Get coordinates from Google Maps',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Allowed Radius Section
                  _SectionHeader(
                    icon: Icons.radar,
                    title: 'Allowed Radius',
                    subtitle: 'Maximum distance from office for check-in',
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _radiusController,
                            decoration: const InputDecoration(
                              labelText: 'Radius (meters)',
                              hintText: '100',
                              prefixIcon: Icon(Icons.straighten),
                              suffixText: 'm',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _QuickRadiusButton(
                                label: '50m',
                                onTap: () => _radiusController.text = '50',
                              ),
                              _QuickRadiusButton(
                                label: '100m',
                                onTap: () => _radiusController.text = '100',
                              ),
                              _QuickRadiusButton(
                                label: '200m',
                                onTap: () => _radiusController.text = '200',
                              ),
                              _QuickRadiusButton(
                                label: '500m',
                                onTap: () => _radiusController.text = '500',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // WiFi Allowlist Section
                  _SectionHeader(
                    icon: Icons.wifi,
                    title: 'Authorized WiFi Networks',
                    subtitle: 'Employees must be connected to one of these',
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _newWifiController,
                                  decoration: const InputDecoration(
                                    labelText: 'WiFi SSID',
                                    hintText: 'Office_Wifi_5G',
                                    prefixIcon: Icon(Icons.wifi),
                                  ),
                                  onSubmitted: (_) => _addWifi(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: _addWifi,
                                child: const Text('Add'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_wifiAllowlist.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No WiFi networks configured.\nEmployees can check in from any network.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _wifiAllowlist.length,
                              itemBuilder: (context, index) {
                                final ssid = _wifiAllowlist[index];
                                return ListTile(
                                  leading: const Icon(
                                    Icons.wifi,
                                    color: Colors.green,
                                  ),
                                  title: Text(ssid),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _removeWifi(ssid),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Info box
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Changes will take effect immediately for all new check-ins.',
                            style: TextStyle(color: Colors.blue.shade700),
                          ),
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

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.indigo),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickRadiusButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickRadiusButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: Text(label),
    );
  }
}
