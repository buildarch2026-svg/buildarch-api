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
      'https://service.localhost/api',
      'https://127.0.0.1/api',
      'https://10.0.2.2/api',
      'https://172.16.0.2/api',
      'https://192.168.1.2/api',
      'https://[::1]/api',
      'https://[fd00::1]/api',
      'https://[fe80::1]/api',
      'https://[::ffff:10.0.0.1]/api',
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
    expect(
      ApiConfiguration(
        baseUrl: 'https://[2606:4700:4700::1111]/api',
        requireHttps: true,
      ).resolve('user').toString(),
      'https://[2606:4700:4700::1111]/api/user',
    );
  });

  test('production configuration uses the AWS API and secure Reverb host', () {
    final configuration = ApiConfiguration(
      baseUrl: 'https://api.buildarchsolutions.com/api/',
      requireHttps: true,
    );

    expect(
      configuration.resolve('user').toString(),
      'https://api.buildarchsolutions.com/api/user',
    );

    final socket = configuration.resolveChatSocket(
      appKey: 'production-key',
      host: 'ws.buildarchsolutions.com',
      port: 443,
      scheme: 'https',
    );
    expect(socket.scheme, 'wss');
    expect(socket.host, 'ws.buildarchsolutions.com');
    expect(socket.port, 443);
    expect(socket.path, '/app/production-key');
  });

  test('release configuration rejects insecure or local Reverb endpoints', () {
    final configuration = ApiConfiguration(
      baseUrl: 'https://api.buildarchsolutions.com/api',
      requireHttps: true,
    );
    for (final values in [
      (host: 'ws.buildarchsolutions.com', port: 443, scheme: 'http'),
      (host: '127.0.0.1', port: 443, scheme: 'https'),
      (host: '192.168.1.2', port: 443, scheme: 'https'),
      (host: 'fd00::1', port: 443, scheme: 'https'),
      (host: 'ws.buildarchsolutions.com', port: 8080, scheme: 'https'),
    ]) {
      expect(
        () => configuration.resolveChatSocket(
          appKey: 'production-key',
          host: values.host,
          port: values.port,
          scheme: values.scheme,
        ),
        throwsA(isA<ApiConfigurationException>()),
      );
    }
  });

  test('builds the Reverb WebSocket URI for local Android forwarding', () {
    final uri = ApiConfiguration(
      baseUrl: 'http://127.0.0.1:8000/api',
    ).resolveChatSocket(
      appKey: 'local-key',
      host: '127.0.0.1',
      port: 8080,
      scheme: 'http',
    );

    expect(uri.scheme, 'ws');
    expect(uri.host, '127.0.0.1');
    expect(uri.port, 8080);
    expect(uri.path, '/app/local-key');
    expect(uri.queryParameters['protocol'], '7');
  });

  test('uses secure Reverb WebSockets for a public HTTPS API', () {
    final uri = ApiConfiguration(
      baseUrl: 'https://api.example.test/api',
      requireHttps: true,
    ).resolveChatSocket(appKey: 'public-key');

    expect(uri.scheme, 'wss');
    expect(uri.host, 'api.example.test');
    expect(uri.path, '/app/public-key');
  });

  test('rejects a missing Reverb application key', () {
    expect(
      () => ApiConfiguration(
        baseUrl: 'https://api.example.test/api',
      ).resolveChatSocket(appKey: ''),
      throwsA(isA<ApiConfigurationException>()),
    );
  });
}
