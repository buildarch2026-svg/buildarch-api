import 'dart:convert';

import 'package:buid_arch/screens/mobile_number_screen.dart';
import 'package:buid_arch/services/auth_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile sign-in shows the OTP API rejection', (tester) async {
    final client = _AuthFlowClient();
    final authApiService = AuthApiService(client: client);
    await tester.pumpWidget(
      MaterialApp(
        home: MobileNumberScreen(authApiService: authApiService),
      ),
    );

    await tester.enterText(find.byType(TextField), '9876543210');
    await tester.tap(find.text('Send OTP'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Verify Your Number'), findsOneWidget);
    expect(client.requests, hasLength(1));
    expect(
      jsonDecode((client.requests.single as http.Request).body),
      {'phone_number': '+919876543210'},
    );

    final otpFields = find.byType(TextField);
    for (var index = 0; index < 6; index++) {
      await tester.enterText(otpFields.at(index), '$index');
      await tester.pump();
    }
    await tester.ensureVisible(find.text('Verify & Proceed'));
    await tester.tap(find.text('Verify & Proceed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Code is incorrect.'), findsOneWidget);
    expect(client.requests, hasLength(2));
    expect(
      jsonDecode((client.requests.last as http.Request).body),
      {'phone_number': '+919876543210', 'code': '012345'},
    );
  });
}

class _AuthFlowClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final response = request.url.path.endsWith('/request')
        ? (200, {'message': 'OTP sent.'})
        : (422, {'message': 'Code is incorrect.'});
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(response.$2))),
      response.$1,
      headers: const {'content-type': 'application/json'},
    );
  }
}
