import 'package:equatable/equatable.dart';

class Rating extends Equatable {
  final String id;
  final String serviceId;
  final String raterId;
  final String ratedId;
  final double score;
  final String? comment;
  final DateTime createdAt;

  const Rating({
    required this.id,
    required this.serviceId,
    required this.raterId,
    required this.ratedId,
    required this.score,
    this.comment,
    required this.createdAt,
  });

  factory Rating.fromMap(Map<String, dynamic> map) {
    return Rating(
      id: map['id'] as String,
      serviceId: map['service_id'] as String,
      raterId: map['rater_id'] as String,
      ratedId: map['rated_id'] as String,
      score: (map['score'] as num?)?.toDouble() ?? 0.0,
      comment: map['comment'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'service_id': serviceId,
      'rater_id': raterId,
      'rated_id': ratedId,
      'score': score,
      if (comment != null) 'comment': comment,
    };
  }

  Rating copyWith({
    String? id,
    String? serviceId,
    String? raterId,
    String? ratedId,
    double? score,
    String? comment,
    DateTime? createdAt,
  }) {
    return Rating(
      id: id ?? this.id,
      serviceId: serviceId ?? this.serviceId,
      raterId: raterId ?? this.raterId,
      ratedId: ratedId ?? this.ratedId,
      score: score ?? this.score,
      comment: comment ?? this.comment,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        serviceId,
        raterId,
        ratedId,
        score,
        comment,
        createdAt,
      ];
}
