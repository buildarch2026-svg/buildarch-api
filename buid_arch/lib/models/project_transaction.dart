class ProjectTransaction {
  const ProjectTransaction({
    required this.id,
    required this.projectId,
    required this.payerUserId,
    required this.payeeName,
    required this.amount,
    required this.currency,
    required this.status,
    required this.paymentMethod,
    required this.paymentType,
    this.payerName,
    this.payeeType,
    this.payeeVpa,
    this.attemptId,
    this.description,
    this.category,
    this.providerReference,
    this.createdAt,
  });

  final String id;
  final String projectId;
  final String payerUserId;
  final String payeeName;
  final double amount;
  final String currency;
  final String status;
  final String paymentMethod;
  final String paymentType;
  final String? payerName;
  final String? payeeType;
  final String? payeeVpa;
  final String? attemptId;
  final String? description;
  final String? category;
  final String? providerReference;
  final DateTime? createdAt;

  factory ProjectTransaction.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final projectId = json['project_id'];
    final payerUserId = json['payer_user_id'];
    final payeeName = json['payee_name'];
    final amount = json['amount'];
    final currency = json['currency'];
    final status = json['status'];
    final paymentMethod = json['payment_method'];
    final paymentType = json['payment_type'];

    if (id == null ||
        projectId == null ||
        payerUserId == null ||
        payeeName is! String ||
        amount is! num ||
        currency is! String ||
        status is! String ||
        paymentMethod is! String ||
        paymentType is! String) {
      throw const FormatException('The project transaction response was invalid.');
    }

    final createdAtRaw = json['created_at'];

    return ProjectTransaction(
      id: id.toString(),
      projectId: projectId.toString(),
      payerUserId: payerUserId.toString(),
      payeeName: payeeName,
      amount: amount.toDouble(),
      currency: currency,
      status: status,
      paymentMethod: paymentMethod,
      paymentType: paymentType,
      payerName: json['payer_name'] is String ? json['payer_name'] as String : null,
      payeeType: json['payee_type'] is String ? json['payee_type'] as String : null,
      payeeVpa: json['payee_vpa'] is String ? json['payee_vpa'] as String : null,
      attemptId: json['attempt_id'] is String ? json['attempt_id'] as String : null,
      description: json['description'] is String ? json['description'] as String : null,
      category: json['category'] is String ? json['category'] as String : null,
      providerReference: json['provider_reference'] is String
          ? json['provider_reference'] as String
          : null,
      createdAt: createdAtRaw is String ? DateTime.tryParse(createdAtRaw) : null,
    );
  }

  String get amountLabel => '$currency ${amount.toStringAsFixed(2)}';
}
