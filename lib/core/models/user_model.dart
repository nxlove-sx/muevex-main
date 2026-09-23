import 'package:equatable/equatable.dart';

enum UserRole { customer, driver, admin }

class User extends Equatable {
  final String id;
  final String email;
  final UserRole role;
  final String name;
  final String? phone;
  final bool isEmailVerified;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const User({
    required this.id,
    required this.email,
    required this.role,
    required this.name,
    this.phone,
    this.isEmailVerified = false,
    required this.createdAt,
    this.updatedAt,
  });

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as String,
      email: map['email'] as String,
      role: UserRole.values.byName(map['role'] as String),
      name: map['name'] as String,
      phone: map['phone'] as String?,
      isEmailVerified: map['is_email_verified'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'role': role.name,
      'name': name,
      'phone': phone,
      'is_email_verified': isEmailVerified,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  User copyWith({
    String? id,
    String? email,
    UserRole? role,
    String? name,
    String? phone,
    bool? isEmailVerified,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      role: role ?? this.role,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    email,
    role,
    name,
    phone,
    isEmailVerified,
    createdAt,
    updatedAt,
  ];
}