import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:buid_arch/services/phone_call_service.dart';

void main() {
  test('normalizes international phone number formatting', () {
    expect(
      PhoneCallService.normalizePhoneNumber('+91 (98765) 43210'),
      '+919876543210',
    );
    expect(
      PhoneCallService.normalizePhoneNumber('0091-98765-43210'),
      '+919876543210',
    );
  });

  test('rejects missing and invalid international numbers', () {
    expect(PhoneCallService.normalizePhoneNumber(null), isNull);
    expect(PhoneCallService.normalizePhoneNumber(''), isNull);
    expect(PhoneCallService.normalizePhoneNumber('9876543210'), isNull);
    expect(PhoneCallService.normalizePhoneNumber('+123'), isNull);
    expect(PhoneCallService.normalizePhoneNumber('+1-800-FLOWERS'), isNull);
  });

  test('opens the external dialer with a tel URI without placing a call',
      () async {
    Uri? openedUri;
    LaunchMode? openedMode;
    final service = PhoneCallService(
      launcher: (uri, {required mode}) async {
        openedUri = uri;
        openedMode = mode;
        return true;
      },
    );

    await service.call('+91 (98765) 43210');

    expect(openedUri.toString(), 'tel:+919876543210');
    expect(openedMode, LaunchMode.externalApplication);
  });

  test('reports unsupported dialers and unavailable numbers', () async {
    final service = PhoneCallService(
      launcher: (uri, {required mode}) async => false,
    );

    await expectLater(
      service.call('+919876543210'),
      throwsA(
        isA<PhoneCallException>().having(
          (error) => error.failure,
          'failure',
          PhoneCallFailure.notSupported,
        ),
      ),
    );
    await expectLater(
      service.call(null),
      throwsA(
        isA<PhoneCallException>().having(
          (error) => error.failure,
          'failure',
          PhoneCallFailure.phoneUnavailable,
        ),
      ),
    );
  });
}
