import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

/// Widget to display admin notifications for check-in/check-out events
class AdminNotificationsPage extends StatefulWidget {
  const AdminNotificationsPage({super.key});

  @override
  State<AdminNotificationsPage> createState() => _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<AdminNotificationsPage> {
  final SupabaseClient _client = Supabase.instance.client;
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _subscribeToNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final response = await _client
          .from('notifications')
          .select('*')
          .order('created_at', ascending: false)
          .limit(50);

      final unread = await _client
          .from('notifications')
          .select('id')
          .eq('is_read', false);

      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(response);
          _unreadCount = (unread as List).length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _subscribeToNotifications() {
    _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(50)
        .listen((data) {
          if (mounted) {
            setState(() {
              _notifications = data;
            });
            _loadNotifications(); // Refresh unread count
          }
        });
  }

  Future<void> _markAsRead(String id) async {
    await _client.from('notifications').update({'is_read': true}).eq('id', id);
    _loadNotifications();
  }

  Future<void> _markAllAsRead() async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('is_read', false);
    _loadNotifications();
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    final dt = DateTime.parse(timestamp).toLocal();
    final now = DateTime.now();

    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return 'Today ${DateFormat.jm().format(dt)}';
    } else if (dt.day == now.day - 1) {
      return 'Yesterday ${DateFormat.jm().format(dt)}';
    }
    return DateFormat('MMM d, h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Notifications'),
            if (_unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_unreadCount',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text(
                'Mark All Read',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotifications,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_off,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You\'ll see check-in/out alerts here',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadNotifications,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _notifications.length,
                itemBuilder: (context, index) {
                  final notif = _notifications[index];
                  final isCheckIn = notif['type'] == 'check_in';
                  final isRead = notif['is_read'] == true;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: isRead ? Colors.white : const Color(0xFFF0F9FF),
                    child: ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isCheckIn
                              ? const Color(0xFF10B981).withOpacity(0.1)
                              : const Color(0xFFF59E0B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isCheckIn ? Icons.login : Icons.logout,
                          color: isCheckIn
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                        ),
                      ),
                      title: Text(
                        notif['title'] ?? '',
                        style: TextStyle(
                          fontWeight: isRead
                              ? FontWeight.normal
                              : FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(notif['message'] ?? ''),
                          const SizedBox(height: 4),
                          Text(
                            _formatTime(notif['created_at']),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      trailing: !isRead
                          ? Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF6366F1),
                                shape: BoxShape.circle,
                              ),
                            )
                          : null,
                      onTap: () {
                        if (!isRead) _markAsRead(notif['id']);
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}
