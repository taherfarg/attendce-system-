import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/services/location_service.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  final _client = Supabase.instance.client;
  final _locationService = LocationService();

  bool _isLoading = true;
  bool _isSaving = false;

  // Controllers
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _qrSecretController = TextEditingController();
  final _wifiController = TextEditingController(); // For adding new wifi

  // State
  double _radius = 100;
  List<String> _wifiList = [];
  TimeOfDay _workStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _workEnd = const TimeOfDay(hour: 18, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    _qrSecretController.dispose();
    _wifiController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final response = await _client.from('system_settings').select('*');
      final settings = <String, dynamic>{};
      for (final s in response) {
        settings[s['setting_key']] = s['setting_value'];
      }

      if (mounted) {
        setState(() {
          _latController.text = settings['office_lat']?.toString() ?? '';
          _lngController.text = settings['office_lng']?.toString() ?? '';
          _qrSecretController.text =
              settings['active_qr_secret']?.toString() ?? '';

          _radius =
              (settings['allowed_radius_meters'] as num?)?.toDouble() ?? 100.0;

          final wifiString = settings['wifi_allowlist']?.toString() ?? '';
          _wifiList = wifiString.isNotEmpty
              ? wifiString
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList()
              : [];

          // Parse working hours if needed, keeping simple for now

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showSnack('Error loading settings: $e', isError: true);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final updates = [
        {
          'setting_key': 'office_lat',
          'setting_value': double.tryParse(_latController.text) ?? 0.0,
        },
        {
          'setting_key': 'office_lng',
          'setting_value': double.tryParse(_lngController.text) ?? 0.0,
        },
        {
          'setting_key': 'allowed_radius_meters',
          'setting_value': _radius.toInt(),
        },
        {'setting_key': 'wifi_allowlist', 'setting_value': _wifiList.join(',')},
        {
          'setting_key': 'active_qr_secret',
          'setting_value': _qrSecretController.text,
        },
      ];

      for (final update in updates) {
        await _client
            .from('system_settings')
            .upsert(update, onConflict: 'setting_key');
      }

      if (mounted) {
        _showSnack('Settings saved successfully!');
      }
    } catch (e) {
      _showSnack('Error saving settings: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLoading = true);
    try {
      final position = await _locationService.getCurrentPosition();
      if (position != null && mounted) {
        setState(() {
          _latController.text = position.latitude.toString();
          _lngController.text = position.longitude.toString();
        });
        _showSnack('Location updated to current position');
      }
    } catch (e) {
      _showSnack('Could not get location: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addWifi() {
    final wifi = _wifiController.text.trim();
    if (wifi.isNotEmpty && !_wifiList.contains(wifi)) {
      setState(() {
        _wifiList.add(wifi);
        _wifiController.clear();
      });
    }
  }

  void _removeWifi(String wifi) {
    setState(() {
      _wifiList.remove(wifi);
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'System Configuration',
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _saveSettings,
        backgroundColor: scheme.primary,
        icon: _isSaving
            ? Container(
                width: 24,
                height: 24,
                padding: const EdgeInsets.all(2),
                child: const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
            : const Icon(Icons.save_rounded),
        label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: scheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(
                    title: 'Office Location',
                    icon: Icons.location_on_outlined,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _Input(
                                controller: _latController,
                                label: 'Latitude',
                                icon: Icons.north_rounded,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _Input(
                                controller: _lngController,
                                label: 'Longitude',
                                icon: Icons.east_rounded,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _useCurrentLocation,
                            icon: const Icon(Icons.my_location_rounded),
                            label: const Text('Use Current Location'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.all(16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                  _SectionHeader(
                    title: 'Geofence Radius',
                    icon: Icons.radar_rounded,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Allowed Check-in Range',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${_radius.toInt()} m',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: scheme.primary,
                            inactiveTrackColor: scheme.primary.withOpacity(0.1),
                            thumbColor: scheme.primary,
                            overlayColor: scheme.primary.withOpacity(0.1),
                          ),
                          child: Slider(
                            value: _radius,
                            min: 50,
                            max: 1000,
                            divisions: 19,
                            label: '${_radius.toInt()} meters',
                            onChanged: (val) => setState(() => _radius = val),
                          ),
                        ),
                        Text(
                          'Employees must be within this distance from the office to check in.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                  _SectionHeader(
                    title: 'WiFi Security',
                    icon: Icons.wifi_lock_rounded,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _wifiController,
                                decoration: InputDecoration(
                                  hintText: 'Add WiFi Name (SSID)',
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                ),
                                onSubmitted: (_) => _addWifi(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: _addWifi,
                              icon: const Icon(Icons.add),
                              style: IconButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _wifiList
                              .map(
                                (wifi) => Chip(
                                  label: Text(wifi),
                                  onDeleted: () => _removeWifi(wifi),
                                  backgroundColor: scheme.primary.withOpacity(
                                    0.05,
                                  ),
                                  deleteIcon: const Icon(Icons.close, size: 16),
                                  side: BorderSide.none,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        if (_wifiList.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'No WiFi networks added. Geofence only.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade400,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                  _SectionHeader(
                    title: 'QR Code Security',
                    icon: Icons.qr_code_2_rounded,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        _Input(
                          controller: _qrSecretController,
                          label: 'Active QR Secret',
                          icon: Icons.key_rounded,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Change this text to invalidate old printed QR codes instantly.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
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
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF6366F1)),
        const SizedBox(width: 10),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}

class _Input extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;

  const _Input({
    required this.controller,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: Colors.grey),
        filled: true,
        fillColor: Colors.grey.shade50,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
        ),
      ),
    );
  }
}
