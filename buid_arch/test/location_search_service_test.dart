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
      expect(requestedHeaders['user-agent'], contains('BUIDARCh'));
      expect(results, hasLength(1));
      expect(results.single.name, 'Kochi, Ernakulam, Kerala, India');
      expect(results.single.latitude, 9.9312);
      expect(results.single.longitude, 76.2673);
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
  });
}
