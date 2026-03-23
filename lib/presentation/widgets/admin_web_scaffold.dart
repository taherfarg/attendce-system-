import 'package:flutter/material.dart';
import '../pages/home/admin_home_page.dart';
import '../pages/home/admin_users_page.dart';
import '../pages/home/admin_reports_page.dart';
import '../pages/home/admin_settings_page.dart';
import '../../core/auth/auth_service.dart';

/// A responsive scaffold for Admin pages.
/// - Mobile: Uses standard Scaffold with AppBar.
/// - Web/Desktop: Uses a Row with Sidebar + Content.
class AdminWebScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? floatingActionButton;
  final List<Widget>? actions;
  final String currentRoute; // 'dashboard', 'users', 'reports', 'settings'

  const AdminWebScaffold({
    super.key,
    required this.title,
    required this.body,
    this.floatingActionButton,
    this.actions,
    required this.currentRoute,
  });

  @override
  Widget build(BuildContext context) {
    // Check if wide screen
    final isWide = MediaQuery.of(context).size.width > 900;

    if (!isWide) {
      // MOBILE LAYOUT
      return Scaffold(
        appBar: AppBar(
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1E293B),
          actions: actions,
        ),
        body: body,
        floatingActionButton: floatingActionButton,
        backgroundColor: const Color(0xFFF8FAFC),
      );
    }

    // WEB LAYOUT
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Row(
        children: [
          // SIDEBAR
          _AdminSidebar(currentRoute: currentRoute),

          // MAIN CONTENT
          Expanded(
            child: Column(
              children: [
                // WEB TOP BAR
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const Spacer(),
                      if (actions != null) ...actions!,
                      const SizedBox(width: 16),
                      // Profile / Logout
                      PopupMenuButton(
                        child: CircleAvatar(
                          backgroundColor: Colors.indigo.shade50,
                          child: const Icon(Icons.person, color: Colors.indigo),
                        ),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            child: const Row(
                              children: [
                                Icon(Icons.logout, color: Colors.red, size: 20),
                                SizedBox(width: 8),
                                Text('Sign Out',
                                    style: TextStyle(color: Colors.red),),
                              ],
                            ),
                            onTap: () async {
                              await AuthService().signOut();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // BODY
                Expanded(
                  child: ClipRect(
                    child: body,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  final String currentRoute;

  const _AdminSidebar({required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B), // Slate 800
        border: Border(
          right: BorderSide(color: Color(0xFF334155)),
        ),
      ),
      child: Column(
        children: [
          // Logo Area
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            alignment: Alignment.centerLeft,
            child: const Row(
              children: [
                Icon(Icons.electric_bolt_rounded,
                    color: Color(0xFF6366F1), size: 28,),
                SizedBox(width: 12),
                Text(
                  'AdminPanel',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF334155), height: 1),
          const SizedBox(height: 16),

          // Navigation Items
          _NavItem(
            icon: Icons.dashboard_rounded,
            label: 'Dashboard',
            isActive: currentRoute == 'dashboard',
            onTap: () => _navigate(context, const AdminHomePage()),
          ),
          _NavItem(
            icon: Icons.people_rounded,
            label: 'Users',
            isActive: currentRoute == 'users',
            onTap: () => _navigate(context, const AdminUsersPage()),
          ),
          _NavItem(
            icon: Icons.analytics_rounded,
            label: 'Reports',
            isActive: currentRoute == 'reports',
            onTap: () => _navigate(context, const AdminReportsPage()),
          ),
          _NavItem(
            icon: Icons.settings_rounded,
            label: 'Settings',
            isActive: currentRoute == 'settings',
            onTap: () => _navigate(context, const AdminSettingsPage()),
          ),
        ],
      ),
    );
  }

  void _navigate(BuildContext context, Widget page) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: isActive ? const Color(0xFF6366F1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive ? Colors.white : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive ? Colors.white : const Color(0xFF94A3B8),
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
