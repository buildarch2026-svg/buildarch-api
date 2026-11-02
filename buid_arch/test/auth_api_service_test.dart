import 'dart:convert';

import 'package:buid_arch/services/auth_api_service.dart';
import 'package:buid_arch/services/api_configuration.dart';
import 'package:buid_arch/models/project_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('project lifecycle requests use authenticated API endpoints', () async {
    final client = _RecordingClient(
      responseBody: {
        'project': {
          'id': 8,
          'name': 'Updated home',
          'location': 'Kochi',
          'type': 'renovation',
          'is_owner': true,
          'is_archived': true,
          'is_deleted': true,
        },
      },
    );
    final service = _testService(client);

    await service.updateProject(
      token: 'test-session-token',
      projectId: '8',
      name: 'Updated home',
      location: 'Kochi',
      type: ProjectType.renovation,
    );
    await service.archiveProject(token: 'test-session-token', projectId: '8');
    await service.deleteProject(token: 'test-session-token', projectId: '8');
    await service.restoreProject(token: 'test-session-token', projectId: '8');
    await service.removeProjectMember(
      token: 'test-session-token',
      projectId: '8',
      memberUserId: 14,
    );

    expect(
      client.requests.map((request) => '${request.method} ${request.url.path}'),
      [
        'PATCH /api/projects/8',
        'POST /api/projects/8/archive',
        'DELETE /api/projects/8',
        'POST /api/projects/8/restore',
        'DELETE /api/projects/8/members/14',
      ],
    );
    for (final request in client.requests) {
      expect(_authorizationHeader(request), startsWith('Bearer '));
      expect(_authorizationHeader(request), 'Bearer test-session-token');
    }
    final updateBody = jsonDecode((client.requests.first as http.Request).body)
        as Map<String, dynamic>;
    expect(updateBody, {
      'name': 'Updated home',
      'location': 'Kochi',
      'type': 'renovation',
      'latitude': null,
      'longitude': null,
    });
  });

  test('profile phone OTP request sends the session as a bearer token',
      () async {
    final client = _RecordingClient();
    final service = _testService(client);

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

  test('project transaction requests send the saved session as a bearer token',
      () async {
    final client = _RecordingClient(
      responseBody: {
        'transactions': [
          {
            'id': 8,
            'project_id': 3,
            'payer_user_id': 12,
            'payee_name': 'Build Mart',
            'amount': 1250.50,
            'currency': 'INR',
            'status': 'pending',
            'payment_method': 'UPI',
            'payment_type': 'provider',
          },
        ],
        'transaction': {
          'id': 8,
          'project_id': 3,
          'payer_user_id': 12,
          'payee_name': 'Build Mart',
          'amount': 1250.50,
          'currency': 'INR',
          'status': 'pending',
          'payment_method': 'UPI',
          'payment_type': 'provider',
        },
      },
    );
    final service = _testService(client);

    await service.getProjectTransactions(
      token: 'test-session-token',
      projectId: '3',
    );
    await service.createProjectTransaction(
      token: 'test-session-token',
      projectId: '3',
      payeeName: 'Build Mart',
      payeeType: 'shop',
      amount: 1250.50,
      currency: 'INR',
      status: 'pending',
      paymentMethod: 'UPI',
      paymentType: 'provider',
    );
    await service.updateProjectTransactionStatus(
      token: 'test-session-token',
      projectId: '3',
      transactionId: '8',
      status: 'completed',
    );

    expect(client.requests, hasLength(3));
    const requestNames = ['list', 'create', 'update status'];
    for (var index = 0; index < client.requests.length; index++) {
      expect(
        _authorizationHeader(client.requests[index]) ==
            'Bearer test-session-token',
        isTrue,
        reason:
            'The transaction ${requestNames[index]} request lost its token.',
      );
    }
  });

  test('notification requests send the saved session as a bearer token',
      () async {
    final client = _RecordingClient(
      responseBody: {'notifications': [], 'unread_count': 0},
    );
    final service = _testService(client);

    await service.getNotifications(token: 'test-session-token');
    await service.markNotificationRead(
      token: 'test-session-token',
      notificationId: '4',
    );

    expect(client.requests, hasLength(2));
    for (final request in client.requests) {
      expect(
        _authorizationHeader(request) == 'Bearer test-session-token',
        isTrue,
        reason: 'A notification request lost its session token.',
      );
    }
  });

  test('OTP request sends a normalized phone number to the correct endpoint',
      () async {
    final client = _RecordingClient();
    final service = _testService(client);

    await service.requestOtp('+1 (415) 555-2671');

    final request = client.requests.single as http.Request;
    expect(request.url.path, '/api/auth/otp/request');
    expect(jsonDecode(request.body), {'phone_number': '+14155552671'});
    expect(request.headers['Accept'], 'application/json');
  });

  test('OTP rate-limit errors retain the retry delay', () async {
    final service = _testService(
      _RecordingClient(
        statusCode: 429,
        responseBody: {'message': 'Too Many Attempts.'},
        responseHeaders: {'retry-after': '540'},
      ),
    );

    await expectLater(
      service.requestOtp('+14155552671'),
      throwsA(
        isA<AuthApiException>()
            .having((error) => error.statusCode, 'statusCode', 429)
            .having(
              (error) => error.retryAfterSeconds,
              'retryAfterSeconds',
              540,
            ),
      ),
    );
  });

  test('unconfigured API URL fails with actionable configuration guidance',
      () async {
    final service = AuthApiService(
      client: _RecordingClient(),
      configuration: ApiConfiguration(baseUrl: ''),
    );

    await expectLater(
      service.requestOtp('+14155552671'),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.message,
          'message',
          contains('--dart-define=API_BASE_URL'),
        ),
      ),
    );
  });

  test('OTP verification returns a validated session', () async {
    final client = _RecordingClient(
      responseBody: {
        'verified': true,
        'token': ' session-token ',
        'user': {'id': 12, 'profile_complete': false},
      },
    );
    final service = _testService(client);

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
      final service = _testService(
        _RecordingClient(responseBody: responseBody),
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
    final service =
        _testService(_RecordingClient(responseBody: {'verified': true}));

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
    final service = _testService(client);

    final session = await service.signInWithGoogle(idToken: 'google-id-token');

    expect(session['token'], 'google-session');
    expect(session['user'], {'id': 24, 'profile_complete': true});
    final request = client.requests.single as http.Request;
    expect(request.url.path, '/api/auth/google');
    expect(jsonDecode(request.body), {'id_token': 'google-id-token'});
  });

  test('OTP API errors retain server message and status code', () async {
    final service = _testService(
      _RecordingClient(
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

AuthApiService _testService(http.Client client) => AuthApiService(
      client: client,
      configuration: ApiConfiguration(
        baseUrl: 'http://127.0.0.1:8000/api',
      ),
    );

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
    this.responseHeaders = const {},
  });

  final int statusCode;
  final Map<String, dynamic> responseBody;
  final Map<String, String> responseHeaders;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final body = utf8.encode(jsonEncode(responseBody));
    return http.StreamedResponse(
      Stream.value(body),
      statusCode,
      headers: {
        'content-type': 'application/json',
        ...responseHeaders,
      },
    );
  }
}
