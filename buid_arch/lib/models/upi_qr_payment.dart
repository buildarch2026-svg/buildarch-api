class UpiQrPayment {
  const UpiQrPayment({
    required this.vpa,
    required this.name,
    this.amount,
    this.note,
    this.merchantCode,
  });

  final String vpa;
  final String name;
  final double? amount;
  final String? note;
  final String? merchantCode;

  factory UpiQrPayment.fromQrValue(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'upi' ||
        uri.host.toLowerCase() != 'pay') {
      throw const FormatException('This is not a supported UPI payment QR code.');
    }

    final vpa = uri.queryParameters['pa']?.trim();
    if (vpa == null ||
        !RegExp(r'^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+$').hasMatch(vpa)) {
      throw const FormatException('The QR code does not contain a valid UPI ID.');
    }

    final currency = uri.queryParameters['cu']?.trim().toUpperCase();
    if (currency != null && currency != 'INR') {
      throw const FormatException('Only Indian rupee (INR) payments are supported.');
    }

    final rawAmount = uri.queryParameters['am']?.trim();
    final amount = rawAmount == null || rawAmount.isEmpty
        ? null
        : double.tryParse(rawAmount);
    if (rawAmount != null &&
        rawAmount.isNotEmpty &&
        (amount == null || amount <= 0 || amount > 100000)) {
      throw const FormatException('The QR code contains an invalid payment amount.');
    }

    final name = uri.queryParameters['pn']?.trim();
    return UpiQrPayment(
      vpa: vpa,
      name: name == null || name.isEmpty ? vpa : name,
      amount: amount,
      note: uri.queryParameters['tn']?.trim(),
      merchantCode: uri.queryParameters['mc']?.trim(),
    );
  }
}
