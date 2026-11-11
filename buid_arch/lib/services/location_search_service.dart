import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class LocationSearchException implements Exception {
  const LocationSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LocationSearchResult {
  const LocationSearchResult({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.placeName,
    this.street,
    this.locality,
    this.city,
    this.state,
    this.postalCode,
    this.country,
  });

  final String name;
  final double latitude;
  final double longitude;
  final String? placeName;
  final String? street;
  final String? locality;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;
}

class LocationSearchService {
  LocationSearchService({http.Client? client})
      : _client = client ?? http.Client();

  static final instance = LocationSearchService();

  final http.Client _client;
  DateTime? _lastRequestAt;

  Future<List<LocationSearchResult>> search(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      throw const LocationSearchException('Enter a place to search for.');
    }

    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      {
        'q': trimmedQuery,
        'format': 'jsonv2',
        'limit': '5',
        'addressdetails': '1',
      },
    );

    try {
      final decoded = await _request(uri);
      if (decoded is! List) {
        throw const LocationSearchException(
          'Could not read the location search response.',
        );
      }

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(_parseResult)
          .toList();
    } on LocationSearchException {
      rethrow;
    } on TimeoutException {
      throw const LocationSearchException(
        'Location search timed out. Check your connection and try again.',
      );
    } on SocketException {
      throw const LocationSearchException(
        'Could not connect to location search. Check your internet connection.',
      );
    } on http.ClientException {
      throw const LocationSearchException(
        'Could not connect to location search. Check your internet connection.',
      );
    } on FormatException {
      throw const LocationSearchException(
        'Could not read the location search response.',
      );
    }
  }

  Future<LocationSearchResult> reverse({
    required double latitude,
    required double longitude,
  }) async {
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const LocationSearchException(
        'The selected coordinates are not valid.',
      );
    }

    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/reverse',
      {
        'lat': '$latitude',
        'lon': '$longitude',
        'format': 'jsonv2',
        'addressdetails': '1',
      },
    );

    try {
      final decoded = await _request(uri);
      if (decoded is! Map<String, dynamic>) {
        throw const LocationSearchException(
          'Could not read the selected location.',
        );
      }
      return _parseResult(decoded);
    } on LocationSearchException {
      rethrow;
    } on TimeoutException {
      throw const LocationSearchException(
        'Location lookup timed out. Check your connection and try again.',
      );
    } on SocketException {
      throw const LocationSearchException(
        'Could not connect to location search. Check your internet connection.',
      );
    } on http.ClientException {
      throw const LocationSearchException(
        'Could not connect to location search. Check your internet connection.',
      );
    } on FormatException {
      throw const LocationSearchException(
        'Could not read the location search response.',
      );
    }
  }

  Future<Object?> _request(Uri uri) async {
    final previousRequestAt = _lastRequestAt;
    if (previousRequestAt != null) {
      final elapsed = DateTime.now().difference(previousRequestAt);
      if (elapsed < const Duration(seconds: 1)) {
        await Future<void>.delayed(const Duration(seconds: 1) - elapsed);
      }
    }
    _lastRequestAt = DateTime.now();

    final response = await _client.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'BUIDARCh/1.0 (project location picker)',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw const LocationSearchException(
        'Location search is unavailable right now. Please try again.',
      );
    }
    return jsonDecode(response.body);
  }

  LocationSearchResult _parseResult(Map<String, dynamic> result) {
    final name = result['display_name'];
    final latitude = double.tryParse('${result['lat']}');
    final longitude = double.tryParse('${result['lon']}');
    final address = result['address'];
    if (name is! String ||
        name.trim().isEmpty ||
        latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const LocationSearchException(
        'Could not read a location from the search results.',
      );
    }
    return LocationSearchResult(
      name: name,
      latitude: latitude,
      longitude: longitude,
      placeName: _addressValue(
        address,
        const ['name', 'amenity', 'building', 'shop', 'tourism'],
      ),
      street: _addressValue(
        address,
        const ['road', 'pedestrian', 'street'],
      ),
      locality: _addressValue(
        address,
        const ['neighbourhood', 'suburb', 'quarter'],
      ),
      city: _addressValue(
          address, const ['city', 'town', 'village', 'municipality']),
      state: _addressValue(address, const ['state', 'region']),
      postalCode: _addressValue(address, const ['postcode']),
      country: _addressValue(address, const ['country']),
    );
  }

  String? _addressValue(Object? address, List<String> keys) {
    if (address is! Map) return null;
    for (final key in keys) {
      final value = address[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}
