import 'dart:convert';

import 'package:buid_arch/services/auth_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('profile phone OTP request sends the session as a bearer token',
      () async {
    final client = _RecordingClient();
    final service = AuthApiService(client: client);

    await service.requestProfilePhoneOtp(
      token: 'test-session-token',
      phoneNumber: '+14155552671',
    );

    expect(client.requests, hasLength(1));
    expect(
      _authorizationHeader(client.requests.single),
      'Bearer test-session-token',
    );
  });

  test('OTP request sends a normalized phone number to the correct endpoint',
      () async {
    final client = _RecordingClient();
    final service = AuthApiService(client: client);

    await service.requestOtp('+1 (415) 555-2671');

    final request = client.requests.single as http.Request;
    expect(request.url.path, '/api/auth/otp/request');
    expect(jsonDecode(request.body), {'phone_number': '+14155552671'});
    expect(request.headers['Accept'], 'application/json');
  });

  test('OTP verification returns a validated session', () async {
    final client = _RecordingClient(
      responseBody: {
        'verified': true,
        'token': ' session-token ',
        'user': {'id': 12, 'profile_complete': false},
      },
    );
    final service = AuthApiService(client: client);

    final session = await service.verifyOtp(
      phoneNumber: '+14155552671',
      code: '123456',
    );

    expect(session['token'], 'session-token');
    expect(session['user'], {'id': 12, 'profile_complete': false});
    final request = client.requests.single as http.Request;
    expect(request.url.path, '/api/auth/otp/verify');
    expect(jsonDecode(request.body), {
      'phone_number': '+14155552671',
      'code': '123456',
    });
  });

  for (final responseBody in <Map<String, dynamic>>[
    {
      'verified': true,
      'user': {'id': 12, 'profile_complete': true}
    },
    {
      'verified': true,
      'token': ' ',
      'user': {'id': 12, 'profile_complete': true},
    },
    {'verified': true, 'token': 'session-token', 'user': null},
    {
      'verified': true,
      'token': 'session-token',
      'user': {'id': 0, 'profile_complete': true},
    },
    {
      'verified': true,
      'token': 'session-token',
      'user': {'id': 12, 'profile_complete': 'true'},
    },
  ]) {
    test('OTP verification rejects malformed session: $responseBody', () async {
      final service = AuthApiService(
        client: _RecordingClient(responseBody: responseBody),
      );

      await expectLater(
        service.verifyOtp(
          phoneNumber: '+14155552671',
          code: '123456',
        ),
        throwsA(
          isA<AuthApiException>().having(
            (error) => error.message,
            'message',
            'The sign-in response was invalid. Please try again.',
          ),
        ),
      );
    });
  }

  test('Google sign-in rejects a verified response without a session',
      () async {
    final service = AuthApiService(
      client: _RecordingClient(responseBody: {'verified': true}),
    );

    await expectLater(
      service.signInWithGoogle(idToken: 'google-id-token'),
      throwsA(isA<AuthApiException>()),
    );
  });

  test('Google sign-in posts the ID token and validates the returned session',
      () async {
    final client = _RecordingClient(
      responseBody: {
        'verified': true,
        'token': 'google-session',
        'user': {'id': 24, 'profile_complete': true},
      },
    );
    final service = AuthApiService(client: client);

    final session = await service.signInWithGoogle(idToken: 'google-id-token');

    expect(session['token'], 'google-session');
    expect(session['user'], {'id': 24, 'profile_complete': true});
    final request = client.requests.single as http.Request;
    expect(request.url.path, '/api/auth/google');
    expect(jsonDecode(request.body), {'id_token': 'google-id-token'});
  });

  test('OTP API errors retain server message and status code', () async {
    final service = AuthApiService(
      client: _RecordingClient(
        statusCode: 422,
        responseBody: {'message': 'Code is incorrect.'},
      ),
    );

    await expectLater(
      service.verifyOtp(
        phoneNumber: '+14155552671',
        code: '123456',
      ),
      throwsA(
        isA<AuthApiException>()
            .having((error) => error.statusCode, 'statusCode', 422)
            .having((error) => error.message, 'message', 'Code is incorrect.'),
      ),
    );
  });
}

String? _authorizationHeader(http.BaseRequest request) {
  for (final header in request.headers.entries) {
    if (header.key.toLowerCase() == 'authorization') return header.value;
  }
  return null;
}

class _RecordingClient extends http.BaseClient {
  _RecordingClient({
    this.statusCode = 200,
    this.responseBody = const {},
  });

  final int statusCode;
  final Map<String, dynamic> responseBody;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final body = utf8.encode(jsonEncode(responseBody));
    return http.StreamedResponse(
      Stream.value(body),
      statusCode,
      headers: const {'content-type': 'application/json'},
    );
  }
}
