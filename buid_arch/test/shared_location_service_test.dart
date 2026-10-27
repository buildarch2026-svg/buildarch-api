import 'package:buid_arch/services/shared_location_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedLocationService', () {
    final service = SharedLocationService.instance;

    test('parses coordinates from a Google Maps query link', () {
      final location = service.parse(
        'https://maps.google.com/?q=9.9312%2C76.2673',
      );

      expect(location?.latitude, 9.9312);
      expect(location?.longitude, 76.2673);
    });

    test('parses coordinates from a Google Maps place link', () {
      final location = service.parse(
        'https://www.google.com/maps/place/Kochi/@9.9312,76.2673,16z',
      );

      expect(location?.latitude, 9.9312);
      expect(location?.longitude, 76.2673);
    });

    test('parses coordinates from Google Maps data parameters', () {
      final location = service.parse(
        'https://www.google.com/maps/place/Kochi/data=!3d9.9312!4d76.2673',
      );

      expect(location?.latitude, 9.9312);
      expect(location?.longitude, 76.2673);
    });

    test('parses geo URIs and standalone shared coordinate pairs', () {
      final geoLocation = service.parse('geo:9.9312,76.2673');
      final coordinateLocation = service.parse('Site pin:\n9.9312, 76.2673');

      expect(geoLocation?.latitude, 9.9312);
      expect(geoLocation?.longitude, 76.2673);
      expect(coordinateLocation?.latitude, 9.9312);
      expect(coordinateLocation?.longitude, 76.2673);
    });

    test('rejects invalid coordinates and unrelated links', () {
      expect(service.parse('https://example.com/maps/@9.9,76.2,16z'), isNull);
      expect(
        service.parse('https://www.google.com/maps/@91,200,16z'),
        isNull,
      );
    });
  });
}
