import 'dart:convert';

import 'package:buid_arch/screens/mobile_number_screen.dart';
import 'package:buid_arch/services/auth_api_service.dart';
import 'package:buid_arch/services/api_configuration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  testWidgets('mobile screen reports API errors and remains on the form',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final client = _RespondingClient(
      statusCode: 503,
      responseBody: {'message': 'OTP delivery is unavailable.'},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MobileNumberScreen(
          authApiService: AuthApiService(
            client: client,
            configuration: ApiConfiguration(
              baseUrl: 'http://127.0.0.1:8000/api',
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '9876543210');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Send OTP'));
    await tester.tap(find.text('Send OTP'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('OTP delivery is unavailable.'), findsOneWidget);
    expect(find.text('Enter Your Number'), findsOneWidget);
    expect(client.requests, hasLength(1));
  });

  testWidgets('mobile screen explains OTP request rate limits', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final client = _RespondingClient(
      statusCode: 429,
      responseBody: {'message': 'Too Many Attempts.'},
      responseHeaders: const {'retry-after': '90'},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MobileNumberScreen(
          authApiService: AuthApiService(
            client: client,
            configuration: ApiConfiguration(
              baseUrl: 'http://127.0.0.1:8000/api',
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '9876543210');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Send OTP'));
    await tester.tap(find.text('Send OTP'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Please wait before requesting another code'),
      findsOneWidget,
    );
    expect(find.textContaining('1 minute and 30 seconds'), findsOneWidget);
    expect(find.textContaining('Your account is not blocked.'), findsOneWidget);
    expect(find.text('Too Many Attempts.'), findsNothing);
  });
}

class _RespondingClient extends http.BaseClient {
  _RespondingClient({
    required this.statusCode,
    required this.responseBody,
    this.responseHeaders = const {},
  });

  final int statusCode;
  final Map<String, dynamic> responseBody;
  final Map<String, String> responseHeaders;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(responseBody))),
      statusCode,
      headers: {'content-type': 'application/json', ...responseHeaders},
    );
  }
}
