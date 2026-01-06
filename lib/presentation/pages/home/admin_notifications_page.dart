import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:grouped_list/grouped_list.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../../core/utils/time_utils.dart';

class AdminNotificationsPage extends StatefulWidget {
  const AdminNotificationsPage({super.key});

  @override
  State<AdminNotificationsPage> createState() => _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<AdminNotificationsPage> {
  final SupabaseClient _client = Supabase.instance.client;
  List<Map<String, dynamic>> _allNotifications = [];
  List<Map<String, dynamic>> _filteredNotifications = [];
  bool _isLoading = true;
  String _selectedFilter = 'All';

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
          .limit(100);

      if (mounted) {
        setState(() {
          _allNotifications = List<Map<String, dynamic>>.from(response);
          _applyFilter();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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
              _allNotifications = data;
              _applyFilter();
            });
          }
        });
  }

  void _applyFilter() {
    setState(() {
      if (_selectedFilter == 'All') {
        _filteredNotifications = _allNotifications;
      } else if (_selectedFilter == 'Unread') {
        _filteredNotifications = _allNotifications
            .where((n) => n['is_read'] == false)
            .toList();
      } else if (_selectedFilter == 'Check-in') {
        _filteredNotifications = _allNotifications
            .where((n) => n['type'] == 'check_in')
            .toList();
      } else if (_selectedFilter == 'Check-out') {
        _filteredNotifications = _allNotifications
            .where((n) => n['type'] == 'check_out')
            .toList();
      }
    });
  }

  Future<void> _markAsRead(String id) async {
    await _client.from('notifications').update({'is_read': true}).eq('id', id);
    // Optimistic update
    final index = _allNotifications.indexWhere((n) => n['id'] == id);
    if (index != -1) {
      setState(() {
        _allNotifications[index]['is_read'] = true;
        _applyFilter();
      });
    }
  }

  Future<void> _deleteNotification(String id) async {
    await _client.from('notifications').delete().eq('id', id);
    // Optimistic update
    setState(() {
      _allNotifications.removeWhere((n) => n['id'] == id);
      _applyFilter();
    });
  }

  Future<void> _markAllAsRead() async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('is_read', false);
    _loadNotifications();
  }

  void _showDetails(Map<String, dynamic> notification) {
    if (notification['is_read'] == false) {
      _markAsRead(notification['id']);
    }

    final data = notification['data'] as Map<String, dynamic>? ?? {};
    final type = notification['type'];
    final isCheckIn = type == 'check_in';
    final color = isCheckIn ? Colors.teal : Colors.orange;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isCheckIn ? Icons.login : Icons.logout,
                    color: color,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification['title'] ?? 'Notification',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM d, y • h:mm a').format(
                          DateTime.parse(notification['created_at']).toLocal(),
                        ),
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              notification['message'] ?? '',
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 32),
            const Text(
              'Details',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            _DetailRow(
              icon: Icons.fingerprint,
              label: 'Method',
              value: data['method']?.toString().toUpperCase() ?? 'UNKNOWN',
            ),
            const SizedBox(height: 16),
            if (data['wifi'] != null) ...[
              _DetailRow(
                icon: Icons.wifi,
                label: 'WiFi Network',
                value: data['wifi'].toString(),
              ),
              const SizedBox(height: 16),
            ],
            if (data['total_minutes'] != null) ...[
              _DetailRow(
                icon: Icons.timer_outlined,
                label: 'Duration',
                value: '${data['total_minutes']} minutes',
              ),
              const SizedBox(height: 16),
            ],
            if (data['location'] != null)
              _DetailRow(
                icon: Icons.location_on_outlined,
                label: 'Location Data',
                value: data['location'].toString(),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unreadCount = _allNotifications.where((n) => !n['is_read']).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: const Color(0xFF1E293B),
          iconSize: 20,
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text('Mark all read'),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  isSelected: _selectedFilter == 'All',
                  onTap: () => _applyFilterWith('All'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Unread',
                  count: unreadCount,
                  isSelected: _selectedFilter == 'Unread',
                  onTap: () => _applyFilterWith('Unread'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Check-in',
                  isSelected: _selectedFilter == 'Check-in',
                  onTap: () => _applyFilterWith('Check-in'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Check-out',
                  isSelected: _selectedFilter == 'Check-out',
                  onTap: () => _applyFilterWith('Check-out'),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: scheme.primary))
          : _filteredNotifications.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 64,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications found',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : GroupedListView<Map<String, dynamic>, DateTime>(
              elements: _filteredNotifications,
              groupBy: (element) {
                final date = DateTime.parse(element['created_at']).toLocal();
                return DateTime(date.year, date.month, date.day);
              },
              groupSeparatorBuilder: (DateTime groupByValue) {
                final now = DateTime.now();
                String text;
                if (groupByValue.year == now.year &&
                    groupByValue.month == now.month &&
                    groupByValue.day == now.day) {
                  text = 'Today';
                } else if (groupByValue.year == now.year &&
                    groupByValue.month == now.month &&
                    groupByValue.day == now.day - 1) {
                  text = 'Yesterday';
                } else {
                  text = DateFormat('MMMM d, y').format(groupByValue);
                }

                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.5,
                    ),
                  ),
                );
              },
              itemBuilder: (context, element) {
                return _NotificationItem(
                  notification: element,
                  onTap: () => _showDetails(element),
                  onDelete: () => _deleteNotification(element['id']),
                  onMarkRead: () => _markAsRead(element['id']),
                );
              },
              padding: const EdgeInsets.only(bottom: 40),
              useStickyGroupSeparators: true,
              floatingHeader: true,
              order: GroupedListOrder.DESC,
            ),
    );
  }

  void _applyFilterWith(String filter) {
    setState(() {
      _selectedFilter = filter;
      _applyFilter();
    });
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isSelected ? scheme.primary : Colors.white;
    final textColor = isSelected ? Colors.white : Colors.grey.shade700;
    final borderColor = isSelected ? scheme.primary : Colors.grey.shade300;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withOpacity(0.2)
                      : scheme.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : scheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotificationItem extends StatelessWidget {
  final Map<String, dynamic> notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onMarkRead;

  const _NotificationItem({
    required this.notification,
    required this.onTap,
    required this.onDelete,
    required this.onMarkRead,
  });

  @override
  Widget build(BuildContext context) {
    final isRead = notification['is_read'] == true;
    final type = notification['type'];
    final isCheckIn = type == 'check_in';
    final time = DateFormat(
      'h:mm a',
    ).format(DateTime.parse(notification['created_at']).toLocal());

    return Slidable(
      key: ValueKey(notification['id']),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        children: [
          if (!isRead)
            SlidableAction(
              onPressed: (_) => onMarkRead(),
              backgroundColor: Colors.blue.shade50,
              foregroundColor: Colors.blue,
              icon: Icons.check_circle_outline,
              label: 'Read',
            ),
          SlidableAction(
            onPressed: (_) => onDelete(),
            backgroundColor: Colors.red.shade50,
            foregroundColor: Colors.red,
            icon: Icons.delete_outline,
            label: 'Delete',
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: isRead ? Colors.transparent : Colors.blue.withOpacity(0.02),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isCheckIn
                      ? Colors.green.withOpacity(0.1)
                      : Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCheckIn ? Icons.login_rounded : Icons.logout_rounded,
                  color: isCheckIn ? Colors.green : Colors.orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification['title'] ?? '',
                            style: TextStyle(
                              fontWeight: isRead
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                              fontSize: 15,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification['message'] ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        color: isRead
                            ? Colors.grey.shade600
                            : Colors.grey.shade800,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!isRead)
                Container(
                  margin: const EdgeInsets.only(left: 12, top: 12),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
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
        Icon(icon, size: 20, color: Colors.grey.shade400),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
