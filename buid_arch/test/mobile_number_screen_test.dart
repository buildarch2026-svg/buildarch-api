import 'dart:convert';

import 'package:buid_arch/screens/mobile_number_screen.dart';
import 'package:buid_arch/services/auth_api_service.dart';
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
          authApiService: AuthApiService(client: client),
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
}

class _RespondingClient extends http.BaseClient {
  _RespondingClient({
    required this.statusCode,
    required this.responseBody,
  });

  final int statusCode;
  final Map<String, dynamic> responseBody;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(responseBody))),
      statusCode,
      headers: const {'content-type': 'application/json'},
    );
  }
}
