import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class CurrentLocationException implements Exception {
  const CurrentLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CurrentDeviceLocation {
  const CurrentDeviceLocation({
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String address;
  final double latitude;
  final double longitude;
}

class CurrentLocationService {
  CurrentLocationService._();

  static final instance = CurrentLocationService._();
  final Geocoding _geocoding = Geocoding();

  Future<String> getCurrentAddress() async =>
      (await getCurrentLocation()).address;

  Future<CurrentDeviceLocation> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const CurrentLocationException(
          'Turn on Location Services and try again.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        throw const CurrentLocationException(
          'Location access is blocked. Allow it in your phone’s app settings, '
          'or enter the location manually.',
        );
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        throw const CurrentLocationException(
          'Location permission was not granted. You can enter the location '
          'manually.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );

      return await getLocationForCoordinates(
        position.latitude,
        position.longitude,
      );
    } on TimeoutException {
      throw const CurrentLocationException(
        'Could not get your location in time. Check GPS reception and try '
        'again, or enter it manually.',
      );
    } on LocationServiceDisabledException {
      throw const CurrentLocationException(
        'Location Services were turned off. Turn them on and try again.',
      );
    } on PermissionDefinitionsNotFoundException {
      throw const CurrentLocationException(
        'Location permission is not configured for this app. Please update '
        'the app or enter the location manually.',
      );
    } on PlatformException {
      throw const CurrentLocationException(
        'Could not read your location or convert it to an address. You can '
        'enter the location manually.',
      );
    }
  }

  Future<CurrentDeviceLocation> getLocationForCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final placemarks = await _geocoding.placemarkFromCoordinates(
        latitude,
        longitude,
      );
      final placemark = placemarks.isEmpty ? null : placemarks.first;
      final parts = <String?>[
        placemark?.subLocality,
        placemark?.locality,
        placemark?.subAdministrativeArea,
        placemark?.administrativeArea,
        placemark?.country,
      ]
          .whereType<String>()
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toSet()
          .toList();

      return CurrentDeviceLocation(
        address: parts.isEmpty
            ? _coordinates(latitude, longitude)
            : parts.join(', '),
        latitude: latitude,
        longitude: longitude,
      );
    } on PlatformException {
      throw const CurrentLocationException(
        'Could not find an address for that map location. Try another point.',
      );
    }
  }

  String _coordinates(double latitude, double longitude) => 'Coordinates: '
      '${latitude.toStringAsFixed(5)}, '
      '${longitude.toStringAsFixed(5)}';
}
