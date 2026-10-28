import 'package:buid_arch/models/upi_qr_payment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UPI QR parses standard pay URL', () {
    final payment = UpiQrPayment.fromQrValue(
      'upi://pay?pa=shop@okaxis&pn=Build%20Mart&am=1250.50&cu=INR&tn=Cement&mc=5411',
    );

    expect(payment.vpa, 'shop@okaxis');
    expect(payment.name, 'Build Mart');
    expect(payment.amount, 1250.50);
    expect(payment.note, 'Cement');
    expect(payment.merchantCode, '5411');
  });

  test('UPI QR rejects non-UPI QR values', () {
    expect(
      () => UpiQrPayment.fromQrValue('https://example.com/pay'),
      throwsFormatException,
    );
  });

  test('UPI QR rejects unsupported currency', () {
    expect(
      () => UpiQrPayment.fromQrValue(
        'upi://pay?pa=shop@okaxis&pn=Shop&am=10&cu=USD',
      ),
      throwsFormatException,
    );
  });
}
