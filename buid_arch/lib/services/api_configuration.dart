import 'package:flutter/foundation.dart';

class ApiConfigurationException implements Exception {
  const ApiConfigurationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiConfiguration {
  ApiConfiguration({
    required String baseUrl,
    bool requireHttps = false,
  })  : _baseUrl = baseUrl,
        _requireHttps = requireHttps;

  factory ApiConfiguration.fromEnvironment() => ApiConfiguration(
        baseUrl: const String.fromEnvironment('API_BASE_URL'),
        requireHttps: kReleaseMode,
      );

  final String _baseUrl;
  final bool _requireHttps;

  Uri resolve(String path) {
    final normalizedPath = path.replaceFirst(RegExp(r'^/+'), '');
    if (normalizedPath.isEmpty) {
      throw const ApiConfigurationException(
        'An API endpoint path is required.',
      );
    }
    return _parseBaseUrl(_baseUrl, requireHttps: _requireHttps)
        .resolve(normalizedPath);
  }

  Uri resolveChatSocket({
    required String appKey,
    String? host,
    int? port,
    String? scheme,
  }) {
    final apiUri = _parseBaseUrl(_baseUrl, requireHttps: _requireHttps);
    final socketScheme =
        scheme?.trim().isNotEmpty == true ? scheme!.trim() : apiUri.scheme;
    final normalizedScheme = switch (socketScheme) {
      'http' => 'ws',
      'https' => 'wss',
      'ws' || 'wss' => socketScheme,
      _ => throw const ApiConfigurationException(
          'The chat WebSocket scheme must be ws, wss, http, or https.',
        ),
    };
    final socketHost =
        host?.trim().isNotEmpty == true ? host!.trim() : apiUri.host;
    if (socketHost.isEmpty || appKey.trim().isEmpty) {
      throw const ApiConfigurationException(
        'The chat WebSocket host and Reverb application key are required.',
      );
    }

    return Uri(
      scheme: normalizedScheme,
      host: socketHost,
      port: port ?? (normalizedScheme == 'wss' ? 443 : 8080),
      path: '/app/${Uri.encodeComponent(appKey.trim())}',
      queryParameters: const {
        'protocol': '7',
        'client': 'js',
        'version': '8.4.0',
        'flash': 'false',
      },
    );
  }

  static Uri _parseBaseUrl(String value, {required bool requireHttps}) {
    final baseUrl = value.trim();
    if (baseUrl.isEmpty) {
      throw const ApiConfigurationException(
        'The API URL is not configured. Start the app with '
        '.\\run_on_phone.ps1 or pass --dart-define=API_BASE_URL=<API URL>.',
      );
    }

    late final Uri uri;
    try {
      uri = Uri.parse(baseUrl);
    } on FormatException {
      throw const ApiConfigurationException(
        'The configured API URL is invalid.',
      );
    }

    if (!uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const ApiConfigurationException(
        'The configured API URL must be an HTTP(S) URL without credentials, '
        'query parameters, or a fragment.',
      );
    }

    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.split('/').last != 'api') {
      throw const ApiConfigurationException(
        'The configured API URL must end in /api.',
      );
    }

    if (requireHttps &&
        (uri.scheme != 'https' ||
            uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '::1')) {
      throw const ApiConfigurationException(
        'Release builds require a publicly reachable HTTPS API URL.',
      );
    }

    return uri.replace(path: '$path/', query: null, fragment: null);
  }
}
