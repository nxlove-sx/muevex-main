import 'package:equatable/equatable.dart';

class Load extends Equatable {
  final String id;
  final String serviceId;
  final String description;
  final double weightKg;
  final String dimensions;
  final String type;
  final bool needsHelp;
  final int floors;
  final DateTime createdAt;

  const Load({
    required this.id,
    required this.serviceId,
    required this.description,
    required this.weightKg,
    required this.dimensions,
    required this.type,
    required this.needsHelp,
    required this.floors,
    required this.createdAt,
  });

  factory Load.fromMap(Map<String, dynamic> map) {
    return Load(
      id: map['id'] as String,
      serviceId: map['service_id'] as String,
      description: map['description'] as String,
      weightKg: (map['weight_kg'] as num?)?.toDouble() ?? 0.0,
      dimensions: map['dimensions'] as String,
      type: map['type'] as String,
      needsHelp: map['needs_help'] as bool? ?? false,
      floors: map['floors'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'service_id': serviceId,
      'description': description,
      'weight_kg': weightKg,
      'dimensions': dimensions,
      'type': type,
      'needs_help': needsHelp,
      'floors': floors,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Load copyWith({
    String? id,
    String? serviceId,
    String? description,
    double? weightKg,
    String? dimensions,
    String? type,
    bool? needsHelp,
    int? floors,
    DateTime? createdAt,
  }) {
    return Load(
      id: id ?? this.id,
      serviceId: serviceId ?? this.serviceId,
      description: description ?? this.description,
      weightKg: weightKg ?? this.weightKg,
      dimensions: dimensions ?? this.dimensions,
      type: type ?? this.type,
      needsHelp: needsHelp ?? this.needsHelp,
      floors: floors ?? this.floors,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        serviceId,
        description,
        weightKg,
        dimensions,
        type,
        needsHelp,
        floors,
        createdAt,
      ];
}
