import 'package:equatable/equatable.dart';

class Payment extends Equatable {
  final String id;
  final String serviceId;
  final double amount;
  final String paymentMethod;
  final String status;
  final DateTime? paidAt;
  final String? transactionId;
  final DateTime createdAt;

  const Payment({
    required this.id,
    required this.serviceId,
    required this.amount,
    required this.paymentMethod,
    required this.status,
    this.paidAt,
    this.transactionId,
    required this.createdAt,
  });

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: map['id'] as String,
      serviceId: map['service_id'] as String,
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: map['payment_method'] as String,
      status: map['status'] as String,
      paidAt: map['paid_at'] != null
          ? DateTime.parse(map['paid_at'] as String)
          : null,
      transactionId: map['transaction_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'service_id': serviceId,
      'amount': amount,
      'payment_method': paymentMethod,
      'status': status,
      if (paidAt != null) 'paid_at': paidAt?.toIso8601String(),
      if (transactionId != null) 'transaction_id': transactionId,
    };
  }

  Payment copyWith({
    String? id,
    String? serviceId,
    double? amount,
    String? paymentMethod,
    String? status,
    DateTime? paidAt,
    String? transactionId,
    DateTime? createdAt,
  }) {
    return Payment(
      id: id ?? this.id,
      serviceId: serviceId ?? this.serviceId,
      amount: amount ?? this.amount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      status: status ?? this.status,
      paidAt: paidAt ?? this.paidAt,
      transactionId: transactionId ?? this.transactionId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    serviceId,
    amount,
    paymentMethod,
    status,
    paidAt,
    transactionId,
    createdAt,
  ];
}