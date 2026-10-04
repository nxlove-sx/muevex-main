import 'package:equatable/equatable.dart';

class CustomerProfile extends Equatable {
  final String id;
  final String userId;
  final String? phone;
  final String? profilePhotoUrl;
  final String? address;
  final double? rating;
  final int? totalServices;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CustomerProfile({
    required this.id,
    required this.userId,
    this.phone,
    this.profilePhotoUrl,
    this.address,
    this.rating,
    this.totalServices,
    this.createdAt,
    this.updatedAt,
  });

  factory CustomerProfile.fromMap(Map<String, dynamic> map) {
    return CustomerProfile(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      phone: map['phone'] as String?,
      profilePhotoUrl: map['profile_photo_url'] as String?,
      address: map['address'] as String?,
      rating: (map['rating'] as num?)?.toDouble(),
      totalServices: map['total_services'] as int?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'phone': phone,
      'profile_photo_url': profilePhotoUrl,
      'address': address,
      'rating': rating,
      'total_services': totalServices,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  CustomerProfile copyWith({
    String? id,
    String? userId,
    String? phone,
    String? profilePhotoUrl,
    String? address,
    double? rating,
    int? totalServices,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomerProfile(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      phone: phone ?? this.phone,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      address: address ?? this.address,
      rating: rating ?? this.rating,
      totalServices: totalServices ?? this.totalServices,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        phone,
        profilePhotoUrl,
        address,
        rating,
        totalServices,
        createdAt,
        updatedAt,
      ];
}
