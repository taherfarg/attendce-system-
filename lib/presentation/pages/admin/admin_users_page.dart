import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin page for managing users (employees)
class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String _filter = 'all'; // all, active, inactive

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);

    try {
      final client = Supabase.instance.client;

      var query = client.from('users').select('''
        id,
        name,
        role,
        status,
        created_at,
        face_profiles(id)
      ''');

      if (_filter == 'active') {
        query = query.eq('status', 'active');
      } else if (_filter == 'inactive') {
        query = query.eq('status', 'inactive');
      }

      final response = await query.order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _users = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading users: $e')));
      }
    }
  }

  Future<void> _addUser() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _AddUserDialog(),
    );

    if (result != null) {
      try {
        // Create auth user first
        final authResponse = await Supabase.instance.client.auth.admin
            .createUser(
              AdminUserAttributes(
                email: result['email']!,
                password: result['password']!,
                emailConfirm: true,
              ),
            );

        if (authResponse.user != null) {
          // Create user profile
          await Supabase.instance.client.from('users').insert({
            'id': authResponse.user!.id,
            'name': result['name']!,
            'role': result['role'] ?? 'employee',
            'status': 'active',
          });

          _loadUsers();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('User created successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error creating user: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _toggleUserStatus(Map<String, dynamic> user) async {
    final newStatus = user['status'] == 'active' ? 'inactive' : 'active';

    try {
      await Supabase.instance.client
          .from('users')
          .update({'status': newStatus})
          .eq('id', user['id']);

      _loadUsers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'User ${newStatus == 'active' ? 'activated' : 'deactivated'}',
            ),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() => _filter = value);
              _loadUsers();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('All Users')),
              const PopupMenuItem(value: 'active', child: Text('Active Only')),
              const PopupMenuItem(
                value: 'inactive',
                child: Text('Inactive Only'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addUser,
        icon: const Icon(Icons.person_add),
        label: const Text('Add User'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No users found'),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadUsers,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _users.length,
                itemBuilder: (context, index) {
                  final user = _users[index];
                  final hasEnrolledFace =
                      (user['face_profiles'] as List?)?.isNotEmpty ?? false;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: user['role'] == 'admin'
                            ? Colors.purple
                            : Colors.blue,
                        child: Icon(
                          user['role'] == 'admin'
                              ? Icons.admin_panel_settings
                              : Icons.person,
                          color: Colors.white,
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(
                            user['name'] ?? 'Unknown',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          if (user['role'] == 'admin')
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.purple.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Admin',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.purple,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: user['status'] == 'active'
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                          ),
                          Text(
                            user['status'] == 'active' ? 'Active' : 'Inactive',
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            hasEnrolledFace ? Icons.face : Icons.face_outlined,
                            size: 16,
                            color: hasEnrolledFace ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasEnrolledFace ? 'Face enrolled' : 'Not enrolled',
                            style: TextStyle(
                              fontSize: 12,
                              color: hasEnrolledFace
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'toggle_status') {
                            _toggleUserStatus(user);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'toggle_status',
                            child: Text(
                              user['status'] == 'active'
                                  ? 'Deactivate'
                                  : 'Activate',
                            ),
                          ),
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

class _AddUserDialog extends StatefulWidget {
  const _AddUserDialog();

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _role = 'employee';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New User'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v?.isEmpty ?? true) return 'Required';
                  if (!v!.contains('@')) return 'Invalid email';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
                validator: (v) {
                  if (v?.isEmpty ?? true) return 'Required';
                  if (v!.length < 6) return 'Min 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  prefixIcon: Icon(Icons.work),
                ),
                items: const [
                  DropdownMenuItem(value: 'employee', child: Text('Employee')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (v) => setState(() => _role = v ?? 'employee'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'name': _nameController.text,
                'email': _emailController.text,
                'password': _passwordController.text,
                'role': _role,
              });
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
