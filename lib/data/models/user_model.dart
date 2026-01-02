/// User model representing an employee or admin user
class UserModel {
  final String id;
  final String name;
  final String email;
  final String role; // 'admin' or 'employee'
  final String status; // 'active' or 'inactive'
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    required this.createdAt,
  });

  /// Create from Supabase JSON response
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unknown',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'employee',
      status: json['status'] as String? ?? 'active',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'role': role, 'status': status};
  }

  /// Check if user is admin
  bool get isAdmin => role == 'admin';

  /// Check if user is active
  bool get isActive => status == 'active';

  /// Create a copy with modified fields
  UserModel copyWith({String? name, String? role, String? status}) {
    return UserModel(
      id: id,
      name: name ?? this.name,
      email: email,
      role: role ?? this.role,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }
}
