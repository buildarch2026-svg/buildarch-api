import 'dart:convert';

import 'package:buid_arch/services/location_search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('LocationSearchService', () {
    test('searches Nominatim and parses place coordinates', () async {
      late Uri requestedUri;
      late Map<String, String> requestedHeaders;
      final service = LocationSearchService(
        client: MockClient((request) async {
          requestedUri = request.url;
          requestedHeaders = request.headers;
          return http.Response(
            jsonEncode([
              {
                'display_name': 'Kochi, Ernakulam, Kerala, India',
                'lat': '9.9312',
                'lon': '76.2673',
                'address': {
                  'road': 'Marine Drive',
                  'suburb': 'Ernakulam',
                  'city': 'Kochi',
                  'state': 'Kerala',
                  'postcode': '682011',
                  'country': 'India',
                },
              },
            ]),
            200,
          );
        }),
      );

      final results = await service.search('Kochi');

      expect(requestedUri.host, 'nominatim.openstreetmap.org');
      expect(requestedUri.queryParameters['q'], 'Kochi');
      expect(requestedUri.queryParameters['format'], 'jsonv2');
      expect(requestedUri.queryParameters['limit'], '5');
      expect(requestedUri.queryParameters['addressdetails'], '1');
      expect(requestedHeaders['user-agent'], contains('BUIDARCh'));
      expect(results, hasLength(1));
      expect(results.single.name, 'Kochi, Ernakulam, Kerala, India');
      expect(results.single.latitude, 9.9312);
      expect(results.single.longitude, 76.2673);
      expect(results.single.street, 'Marine Drive');
      expect(results.single.locality, 'Ernakulam');
      expect(results.single.city, 'Kochi');
      expect(results.single.state, 'Kerala');
      expect(results.single.postalCode, '682011');
      expect(results.single.country, 'India');
    });

    test('rejects empty search terms without making a request', () async {
      final service = LocationSearchService(
        client: MockClient((_) async => http.Response('[]', 200)),
      );

      await expectLater(
        service.search('  '),
        throwsA(isA<LocationSearchException>()),
      );
    });

    test('reports a server error explicitly', () async {
      final service = LocationSearchService(
        client: MockClient((_) async => http.Response('Unavailable', 503)),
      );

      await expectLater(
        service.search('Kochi'),
        throwsA(
          isA<LocationSearchException>().having(
            (error) => error.message,
            'message',
            contains('unavailable'),
          ),
        ),
      );
    });

    test('reverse-geocodes coordinates and parses address details', () async {
      late Uri requestedUri;
      final service = LocationSearchService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response(
            jsonEncode({
              'display_name': 'Marine Drive, Kochi, Kerala, India',
              'lat': '9.9312',
              'lon': '76.2673',
              'address': {
                'road': 'Marine Drive',
                'city': 'Kochi',
                'state': 'Kerala',
                'country': 'India',
              },
            }),
            200,
          );
        }),
      );

      final result =
          await service.reverse(latitude: 9.9312, longitude: 76.2673);

      expect(requestedUri.path, '/reverse');
      expect(requestedUri.queryParameters['lat'], '9.9312');
      expect(requestedUri.queryParameters['lon'], '76.2673');
      expect(requestedUri.queryParameters['format'], 'jsonv2');
      expect(result.name, 'Marine Drive, Kochi, Kerala, India');
      expect(result.street, 'Marine Drive');
      expect(result.city, 'Kochi');
      expect(result.state, 'Kerala');
      expect(result.country, 'India');
    });

    test('rejects invalid coordinates before making a request', () async {
      var requested = false;
      final service = LocationSearchService(
        client: MockClient((_) async {
          requested = true;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        service.reverse(latitude: 91, longitude: 0),
        throwsA(isA<LocationSearchException>()),
      );
      expect(requested, isFalse);
    });
  });
}
