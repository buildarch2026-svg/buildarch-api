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

    final socketPort = port ?? (normalizedScheme == 'wss' ? 443 : 8080);
    if (_requireHttps &&
        (normalizedScheme != 'wss' ||
            socketPort != 443 ||
            _isLocalOrPrivateHost(socketHost))) {
      throw const ApiConfigurationException(
        'Release builds require a public WSS Reverb endpoint on port 443.',
      );
    }

    return Uri(
      scheme: normalizedScheme,
      host: socketHost,
      port: socketPort,
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
        (uri.scheme != 'https' || _isLocalOrPrivateHost(uri.host))) {
      throw const ApiConfigurationException(
        'Release builds require a publicly reachable HTTPS API URL.',
      );
    }

    return uri.replace(path: '$path/', query: null, fragment: null);
  }

  static bool _isLocalOrPrivateHost(String value) {
    final host = value.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal')) {
      return true;
    }

    if (host.contains(':')) return _isLocalOrPrivateIpv6(host);
    return _isPrivateIpv4(host);
  }

  static bool _isPrivateIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((octet) => octet == null || octet < 0 || octet > 255)) {
      return false;
    }

    final first = octets[0]!;
    final second = octets[1]!;
    return first == 0 ||
        first == 10 ||
        first == 127 ||
        (first == 169 && second == 254) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168) ||
        (first == 100 && second >= 64 && second <= 127);
  }

  static bool _isLocalOrPrivateIpv6(String host) {
    if (host == '::' || host == '::1') return true;
    if (host.startsWith('::ffff:')) {
      final mappedAddress = host.substring('::ffff:'.length);
      if (mappedAddress.contains('.')) return _isPrivateIpv4(mappedAddress);

      final parts = host.split(':');
      if (parts.length >= 2) {
        final high = int.tryParse(parts[parts.length - 2], radix: 16);
        final low = int.tryParse(parts[parts.length - 1], radix: 16);
        if (high != null && low != null) {
          return _isPrivateIpv4(
            '${high >> 8}.${high & 0xff}.${low >> 8}.${low & 0xff}',
          );
        }
      }
      return false;
    }

    final firstGroup = host.split(':').firstWhere(
          (group) => group.isNotEmpty,
          orElse: () => '',
        );
    final first = int.tryParse(firstGroup, radix: 16);
    if (first == null) return false;
    return (first & 0xfe00) == 0xfc00 ||
        (first & 0xffc0) == 0xfe80 ||
        (first & 0xffc0) == 0xfec0;
  }
}
