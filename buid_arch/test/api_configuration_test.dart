import 'package:buid_arch/services/api_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves endpoint paths against the configured API root', () {
    final configuration = ApiConfiguration(
      baseUrl: 'https://api.example.test/api/',
    );

    expect(
      configuration.resolve('/projects/12').toString(),
      'https://api.example.test/api/projects/12',
    );
  });

  test('rejects missing and malformed API URLs with configuration guidance',
      () {
    for (final url in ['', 'not a URL', 'http://example.test/v1']) {
      expect(
        () => ApiConfiguration(baseUrl: url).resolve('user'),
        throwsA(isA<ApiConfigurationException>()),
        reason: 'Expected $url to be rejected',
      );
    }
  });

  test('release configuration requires a public HTTPS API root', () {
    for (final url in [
      'http://api.example.test/api',
      'https://localhost/api',
      'https://127.0.0.1/api',
    ]) {
      expect(
        () =>
            ApiConfiguration(baseUrl: url, requireHttps: true).resolve('user'),
        throwsA(isA<ApiConfigurationException>()),
      );
    }

    expect(
      ApiConfiguration(
        baseUrl: 'https://api.example.test/api',
        requireHttps: true,
      ).resolve('user').toString(),
      'https://api.example.test/api/user',
    );
  });
}
