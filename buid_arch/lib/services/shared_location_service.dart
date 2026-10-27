import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class SharedLocationException implements Exception {
  const SharedLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SharedLocation {
  const SharedLocation({
    required this.latitude,
    required this.longitude,
    required this.label,
  });

  final double latitude;
  final double longitude;
  final String label;
}

class SharedLocationService {
  SharedLocationService._() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static final instance = SharedLocationService._();
  static const _channel =
      MethodChannel('com.example.buid_arch/shared_location');
  final _sharedTextController = StreamController<String>.broadcast();

  Stream<String> get sharedTexts => _sharedTextController.stream;

  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (call.method == 'sharedTextReceived' && call.arguments is String) {
      _sharedTextController.add(call.arguments as String);
    }
    return null;
  }

  Future<String?> takeSharedText() async {
    try {
      return await _channel.invokeMethod<String>('takeSharedText');
    } on PlatformException {
      throw const SharedLocationException(
        'Could not read the shared location. Please try sharing it again.',
      );
    }
  }

  SharedLocation? parse(String sharedText) {
    for (final line in sharedText.split(RegExp(r'[\r\n]+'))) {
      final match = RegExp(
        r'^\s*(-?\d{1,2}(?:\.\d+)?)\s*[, ]\s*'
        r'(-?\d{1,3}(?:\.\d+)?)\s*$',
      ).firstMatch(line);
      if (match != null) {
        final location = _locationFromValues(
          match.group(1),
          match.group(2),
          label: 'Shared map location',
        );
        if (location != null) return location;
      }
    }

    final urls = RegExp(
      r'https?://[^\s<>]+',
      caseSensitive: false,
    ).allMatches(sharedText);
    for (final match in urls) {
      final urlText = match.group(0)!.replaceAll(RegExp(r'[),.;]+$'), '');
      final uri = Uri.tryParse(urlText);
      if (uri == null || !_isMapUrl(uri)) continue;

      final location = _locationFromMapUri(uri);
      if (location != null) return location;
    }

    final geoMatch = RegExp(
      r'geo:(-?\d{1,2}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(sharedText);
    if (geoMatch != null) {
      return _locationFromValues(
        geoMatch.group(1),
        geoMatch.group(2),
        label: 'Shared map location',
      );
    }
    return null;
  }

  Future<SharedLocation?> resolve(String sharedText) async {
    final directResult = parse(sharedText);
    if (directResult != null) return directResult;

    final sharedUrls = RegExp(
      r'https?://[^\s<>]+',
      caseSensitive: false,
    )
        .allMatches(sharedText)
        .map((match) => match.group(0)!.replaceAll(RegExp(r'[),.;]+$'), ''))
        .map(Uri.tryParse)
        .whereType<Uri>()
        .where(_isMapUrl)
        .toList();
    final sharedUrl = sharedUrls.isEmpty ? null : sharedUrls.first;
    if (sharedUrl == null ||
        (sharedUrl.host != 'maps.app.goo.gl' && sharedUrl.host != 'goo.gl')) {
      return null;
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      var current = sharedUrl;
      for (var redirectCount = 0; redirectCount < 6; redirectCount++) {
        final request = await client.getUrl(current);
        request.followRedirects = false;
        final response = await request.close();
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (response.isRedirect && location != null) {
          final next = current.resolve(location);
          if (!_isMapUrl(next)) return null;
          current = next;
          final resolved = parse(current.toString());
          if (resolved != null) return resolved;
          continue;
        }
        return parse(current.toString());
      }
      return parse(current.toString());
    } on SocketException {
      throw const SharedLocationException(
        'Could not open the shared map link. Check your internet connection.',
      );
    } on HttpException {
      throw const SharedLocationException(
        'Could not open the shared map link. Try sharing it again.',
      );
    } finally {
      client.close(force: true);
    }
  }

  SharedLocation? _locationFromMapUri(Uri uri) {
    final path = uri.path;
    final atMatch = RegExp(
      r'@(-?\d{1,2}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)',
    ).firstMatch(path);
    if (atMatch != null) {
      return _locationFromValues(
        atMatch.group(1),
        atMatch.group(2),
        label: 'Shared Google Maps location',
      );
    }

    final placeMatch = RegExp(
      r'!3d(-?\d{1,2}(?:\.\d+)?)!4d(-?\d{1,3}(?:\.\d+)?)',
    ).firstMatch(uri.toString());
    if (placeMatch != null) {
      return _locationFromValues(
        placeMatch.group(1),
        placeMatch.group(2),
        label: 'Shared Google Maps location',
      );
    }

    for (final key in const ['q', 'query', 'll', 'center', 'daddr']) {
      final value = uri.queryParameters[key];
      if (value == null) continue;
      final match = RegExp(
        r'(-?\d{1,2}(?:\.\d+)?)\s*[, ]\s*'
        r'(-?\d{1,3}(?:\.\d+)?)',
      ).firstMatch(value);
      if (match != null) {
        return _locationFromValues(
          match.group(1),
          match.group(2),
          label: 'Shared Google Maps location',
        );
      }
    }
    return null;
  }

  SharedLocation? _locationFromValues(
    String? latitudeValue,
    String? longitudeValue, {
    required String label,
  }) {
    final latitude = double.tryParse(latitudeValue ?? '');
    final longitude = double.tryParse(longitudeValue ?? '');
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }
    return SharedLocation(
      latitude: latitude,
      longitude: longitude,
      label: label,
    );
  }

  bool _isMapUrl(Uri uri) {
    final host = uri.host.toLowerCase();
    return host == 'maps.app.goo.gl' ||
        host == 'goo.gl' ||
        host == 'maps.google.com' ||
        host == 'google.com' ||
        host == 'www.google.com' ||
        host == 'maps.google.co.in' ||
        host == 'google.co.in' ||
        host == 'www.google.co.in';
  }
}
