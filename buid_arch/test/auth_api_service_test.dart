import 'dart:convert';
import 'dart:typed_data';

import 'package:buid_arch/services/auth_api_service.dart';
import 'package:buid_arch/services/api_configuration.dart';
import 'package:buid_arch/models/job_portal.dart';
import 'package:buid_arch/models/project_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

void main() {
  test('job search sends authenticated filters and parses pagination',
      () async {
    final client = _RecordingClient(
      responseBody: {
        'jobs': {
          'data': [
            {
              'id': 42,
              'title': 'Site Architect',
              'employment_type': 'Full Time',
              'location_name': 'Springfield',
              'status': 'published',
              'skills': ['Planning'],
              'category': {'id': 2, 'slug': 'architect', 'name': 'Architect'},
              'company': {
                'id': 7,
                'user_id': 33,
                'community_profile_id': 44,
                'name': 'Build Arch Works',
              },
            },
          ],
          'current_page': 1,
          'last_page': 3,
        },
        'categories': [],
      },
    );
    final page = await _testService(client).getConstructionJobs(
      token: 'test-session-token',
      query: 'architect',
      category: 'architect',
      location: 'Springfield',
      page: 1,
    );

    final request = client.requests.single as http.Request;
    expect(request.url.path, '/api/jobs');
    expect(request.url.queryParameters, {
      'page': '1',
      'q': 'architect',
      'category': 'architect',
      'sort': 'latest',
      'location': 'Springfield',
    });
    expect(_authorizationHeader(request), startsWith('Bearer '));
    expect(page.items.single, isA<ConstructionJob>());
    expect(page.items.single.title, 'Site Architect');
    expect(page.items.single.category?.name, 'Architect');
    expect(page.items.single.company?.userId, 33);
    expect(page.items.single.company?.communityProfileId, 44);
    expect(page.hasMore, isTrue);
  });

  test('Community feed sends auth and parses categories and pagination',
      () async {
    final client = _RecordingClient(
      responseBody: {
        'categories': [
          {'id': 3, 'slug': 'construction', 'name': 'Construction'},
        ],
        'posts': {
          'data': [],
          'current_page': 1,
          'last_page': 2,
        },
      },
    );
    final result = await _testService(client).getCommunityFeed(
      token: 'test-session-token',
      category: 'construction',
    );

    final request = client.requests.single as http.Request;
    expect(request.url.path, '/api/community/feed');
    expect(
        request.url.queryParameters, {'page': '1', 'category': 'construction'});
    expect(_authorizationHeader(request), startsWith('Bearer '));
    expect(result.categories.single.name, 'Construction');
    expect(result.page.currentPage, 1);
    expect(result.page.hasMore, isTrue);
  });

  test('Community categories can load for the profile post composer', () async {
    final client = _RecordingClient(
      responseBody: {
        'categories': [
          {'id': 3, 'slug': 'construction', 'name': 'Construction'},
        ],
      },
    );
    final categories = await _testService(client).getCommunityCategories(
      token: 'test-session-token',
    );

    final request = client.requests.single as http.Request;
    expect(request.url.path, '/api/community/categories');
    expect(_authorizationHeader(request), startsWith('Bearer '));
    expect(categories.single.name, 'Construction');
  });

  test('Community post creation uploads multiple image files', () async {
    final client = _RecordingClient(
      responseBody: {
        'post': {
          'id': 42,
          'content': 'A post with several images',
          'image_urls': [
            'https://example.test/first.jpg',
            'https://example.test/second.jpg',
          ],
          'likes_count': 0,
          'comments_count': 0,
          'liked_by_me': false,
          'author': {
            'id': 7,
            'user_id': 9,
            'display_name': 'Community Member',
            'profession': 'Designer',
            'profession_type': 'Designer',
            'posts_count': 1,
          },
        },
      },
    );
    final images = [
      XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'first.jpg',
        mimeType: 'image/jpeg',
      ),
      XFile.fromData(
        Uint8List.fromList([4, 5, 6, 7]),
        name: 'second.jpg',
        mimeType: 'image/jpeg',
      ),
    ];

    final post = await _testService(client).createCommunityPost(
      token: 'test-session-token',
      content: 'A post with several images',
      images: images,
    );

    final request = client.requests.single as http.MultipartRequest;
    expect(request.url.path, '/api/community/posts');
    expect(_authorizationHeader(request), startsWith('Bearer '));
    expect(request.files, hasLength(2));
    expect(request.files.map((file) => file.field), everyElement('images[]'));
    expect(request.files.map((file) => file.length), [3, 4]);
    expect(post.imageUrls, [
      'https://example.test/first.jpg',
      'https://example.test/second.jpg',
    ]);
    expect(post.imageUrl, 'https://example.test/first.jpg');
  });

  test('Community profile image upload sends image bytes as multipart data',
      () async {
    final client = _RecordingClient(
      responseBody: {
        'profile': {
          'id': 42,
          'user_id': 9,
          'display_name': 'Arun Kumar',
          'profession': 'Designer',
          'profession_type': 'Designer',
          'posts_count': 0,
          'profile_image_url': 'https://example.test/profile.jpg',
        },
      },
    );
    final image = XFile.fromData(
      Uint8List.fromList([1, 2, 3, 4]),
      name: 'profile.jpg',
      mimeType: 'image/jpeg',
    );
    final profile = await _testService(client).updateCommunityProfileImage(
      token: 'test-session-token',
      image: image,
    );

    final request = client.requests.single as http.MultipartRequest;
    expect(request.url.path, '/api/community/profile/image');
    expect(_authorizationHeader(request), startsWith('Bearer '));
    expect(request.files.single.field, 'profile_image');
    expect(request.files.single.length, 4);
    expect(profile.profileImageUrl, 'https://example.test/profile.jpg');
  });

  test('Community registration sends the username and selected location',
      () async {
    final client = _RecordingClient(
      responseBody: {
        'profile': {
          'id': 42,
          'user_id': 9,
          'display_name': 'Malu',
          'profession': 'Community member',
          'profession_type': null,
          'posts_count': 0,
          'location': 'Kochi, Kerala',
        },
      },
    );
    final profile = await _testService(client).registerCommunityProfile(
      token: 'test-session-token',
      displayName: 'Malu',
      location: 'Kochi, Kerala',
    );

    final request = client.requests.single as http.MultipartRequest;
    expect(request.url.path, '/api/community/profile');
    expect(_authorizationHeader(request), startsWith('Bearer '));
    expect(request.fields['display_name'], 'Malu');
    expect(request.fields['location'], 'Kochi, Kerala');
    expect(request.fields['guidelines_accepted'], '1');
    expect(profile.displayName, 'Malu');
    expect(profile.location, 'Kochi, Kerala');
  });

  test('Community member profile parses phone details for accepted contacts',
      () async {
    final client = _RecordingClient(
      responseBody: {
        'profile': {
          'id': 42,
          'user_id': 9,
          'display_name': 'Arun Kumar',
          'profession': 'Painter',
          'profession_type': 'Other',
          'posts_count': 3,
          'phone_number': '+919876543210',
        },
      },
    );
    final profile = await _testService(client).getCommunityMemberProfile(
      token: 'test-session-token',
      profileId: 42,
    );

    final request = client.requests.single as http.Request;
    expect(request.url.path, '/api/community/profiles/42');
    expect(_authorizationHeader(request), startsWith('Bearer '));
    expect(profile.userId, 9);
    expect(profile.phoneNumber, '+919876543210');
  });

  test('Community contact status uses the authenticated member endpoint',
      () async {
    final client = _RecordingClient(
      responseBody: {
        'status': 'outgoing_pending',
        'request_id': 91,
        'blocked_by_me': false,
        'phone_number': null,
      },
    );
    final status = await _testService(client).getCommunityContactStatus(
      token: 'test-session-token',
      userId: 27,
    );

    final request = client.requests.single as http.Request;
    expect(request.url.path, '/api/community/members/27/contact-status');
    expect(_authorizationHeader(request), 'Bearer test-session-token');
    expect(status.status, 'outgoing_pending');
    expect(status.requestId, 91);
  });

  test('Community call requests post the target and parse member profiles',
      () async {
    final client = _RecordingClient(
      responseBody: {
        'request': {
          'id': 91,
          'requester_id': 14,
          'receiver_id': 27,
          'status': 'pending',
          'requester': {
            'user_id': 14,
            'profile_id': 4,
            'display_name': 'Arun Kumar',
            'profession': 'Painter',
            'location': 'Kochi',
          },
          'receiver': {
            'user_id': 27,
            'profile_id': 9,
            'display_name': 'Meera',
            'profession': 'Designer',
            'location': 'Thrissur',
          },
        },
      },
    );
    final requestModel = await _testService(client).sendCommunityContactRequest(
      token: 'test-session-token',
      receiverId: 27,
    );

    final request = client.requests.single as http.Request;
    expect(request.method, 'POST');
    expect(request.url.path, '/api/community/contact-requests');
    expect(jsonDecode(request.body), {'receiver_id': 27});
    expect(_authorizationHeader(request), 'Bearer test-session-token');
    expect(requestModel.id, 91);
    expect(requestModel.requester.displayName, 'Arun Kumar');
    expect(requestModel.receiver.profession, 'Designer');
  });

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

  test('account access and upgrade use authenticated account endpoints',
      () async {
    final accessClient = _RecordingClient(
      responseBody: {
        'has_main_app_access': true,
        'roles': ['contractor'],
      },
    );
    final access = await _testService(accessClient)
        .getAccountAccess(token: 'test-session-token');
    expect(access['has_main_app_access'], isTrue);
    expect(
      (accessClient.requests.single as http.Request).url.path,
      '/api/account/access',
    );
    expect(
      _authorizationHeader(accessClient.requests.single),
      startsWith('Bearer '),
    );

    final upgradeClient = _RecordingClient(
      responseBody: {
        'user': {
          'id': 42,
          'name': 'Community Member',
          'role': 'designer',
        },
      },
    );
    final user = await _testService(upgradeClient).upgradeAccount(
      token: 'test-session-token',
      role: 'designer',
      name: 'Community Member',
      location: 'Kochi, Kerala',
    );
    expect(user['id'], 42);
    final request = upgradeClient.requests.single as http.Request;
    expect(request.url.path, '/api/account/upgrade');
    expect(_authorizationHeader(request), startsWith('Bearer '));
    expect(jsonDecode(request.body), {
      'role': 'designer',
      'name': 'Community Member',
      'location': 'Kochi, Kerala',
    });
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

  test('push token registration and removal use authenticated JSON requests',
      () async {
    final client = _RecordingClient();
    final service = _testService(client);

    await service.registerPushToken(
      token: 'test-session-token',
      firebaseToken: 'fcm-device-token-0123456789abcdef',
      platform: 'android',
    );
    await service.removePushToken(
      token: 'test-session-token',
      firebaseToken: 'fcm-device-token-0123456789abcdef',
    );

    expect(
      client.requests.map((request) => '${request.method} ${request.url.path}'),
      ['POST /api/push-tokens', 'DELETE /api/push-tokens'],
    );
    final registerBody = jsonDecode(
      (client.requests.first as http.Request).body,
    ) as Map<String, dynamic>;
    expect(registerBody, {
      'token': 'fcm-device-token-0123456789abcdef',
      'platform': 'android',
    });
    final removeRequest = client.requests.last as http.Request;
    expect(
      jsonDecode(removeRequest.body),
      {'token': 'fcm-device-token-0123456789abcdef'},
    );
    for (final request in client.requests) {
      expect(_authorizationHeader(request), 'Bearer test-session-token');
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

  test('HTTP errors without a JSON message include the response status',
      () async {
    final service = _testService(
      _RecordingClient(
        statusCode: 500,
        responseText: '<html>Internal Server Error</html>',
      ),
    );

    await expectLater(
      service.requestOtp('+14155552671'),
      throwsA(
        isA<AuthApiException>()
            .having((error) => error.statusCode, 'statusCode', 500)
            .having(
              (error) => error.message,
              'message',
              'The server returned an unexpected response (HTTP 500). '
                  'Please try again.',
            ),
      ),
    );
  });

  test('chat inbox and read-channel APIs use the authenticated session',
      () async {
    final client = _RecordingClient(
      responseBody: {
        'auth': 'signed-channel-auth',
        'chats': [
          {
            'id': 'group:8:group',
            'type': 'group',
            'conversation_id': 2,
            'participant_user_id': null,
            'project_id': 8,
            'project_name': 'Kitchen renovation',
            'project_location': 'Kochi',
            'project_type': 'renovation',
            'project_latitude': 9.9,
            'project_longitude': 76.2,
            'is_owner': true,
            'name': 'Kitchen renovation Team',
            'counterpart_user_id': null,
            'counterpart_role': null,
            'counterpart_designation': null,
            'last_message': null,
            'last_message_at': null,
            'unread_count': 0,
          },
          {
            'id': 'direct:8:14',
            'type': 'direct',
            'conversation_id': 3,
            'participant_user_id': 14,
            'project_id': 8,
            'project_name': 'Kitchen renovation',
            'project_location': 'Kochi',
            'project_type': 'renovation',
            'project_latitude': 9.9,
            'project_longitude': 76.2,
            'is_owner': true,
            'name': 'Project Designer',
            'counterpart_user_id': 14,
            'counterpart_role': 'designer',
            'counterpart_designation': 'Interior Designer',
            'last_message': {
              'body': 'I will update the drawing.',
              'message_type': 'text',
            },
            'last_message_at': '2026-11-02T10:00:00+00:00',
            'unread_count': 2,
          },
        ],
      },
    );
    final service = _testService(client);

    final chats = await service.getChats(token: 'test-session-token');
    expect(chats, hasLength(2));
    expect(chats.first.projectName, 'Kitchen renovation');
    expect(chats.first.toProject().type, ProjectType.renovation);
    expect(chats[1].toCounterpart().role, 'designer');
    expect(chats[1].lastMessage, 'I will update the drawing.');

    final auth = await service.authenticateChatChannel(
      token: 'test-session-token',
      socketId: '123.456',
      channelName: 'private-project-chat.group.8',
    );
    expect(auth['auth'], 'signed-channel-auth');
    await service.markProjectGroupChatRead(
      token: 'test-session-token',
      projectId: '8',
    );
    await service.markDirectChatRead(
      token: 'test-session-token',
      projectId: '8',
      memberUserId: 14,
    );

    expect(
      client.requests.map((request) => '${request.method} ${request.url.path}'),
      [
        'GET /api/chats',
        'POST /api/broadcasting/auth',
        'POST /api/projects/8/group-chat/read',
        'POST /api/projects/8/members/14/messages/read',
      ],
    );
    for (final request in client.requests) {
      expect(_authorizationHeader(request), startsWith('Bearer '));
    }
    final authBody = jsonDecode(
      (client.requests[1] as http.Request).body,
    ) as Map<String, dynamic>;
    expect(authBody, {
      'socket_id': '123.456',
      'channel_name': 'private-project-chat.group.8',
    });
  });

  test('forwarding a chat message sends source and target conversations',
      () async {
    final client = _RecordingClient(
      responseBody: {
        'message': {
          'id': 42,
          'body': 'Review the plan',
          'message_type': 'text',
          'sender_user_id': 12,
          'sender_name': 'Home Owner',
          'forwarded_from_name': 'Designer',
        },
      },
    );
    final service = _testService(client);

    final message = await service.forwardChatMessage(
      token: 'test-session-token',
      projectId: '8',
      sourceType: 'direct',
      sourceMessageId: 31,
      sourceMemberUserId: 14,
      targetType: 'group',
    );

    expect(message.forwardedFromName, 'Designer');
    final request = client.requests.single as http.Request;
    expect(request.url.path, '/api/projects/8/chat/forward');
    expect(jsonDecode(request.body), {
      'source_type': 'direct',
      'source_message_id': 31,
      'source_member_user_id': 14,
      'target_type': 'group',
    });
    expect(_authorizationHeader(request), startsWith('Bearer '));
  });

  test('private chat files include the authorized conversation participant',
      () async {
    final client = _RecordingClient(
      responseBody: {
        'files': [
          {
            'id': 42,
            'body': null,
            'message_type': 'image',
            'attachment_name': 'design.jpg',
            'attachment_mime_type': 'image/jpeg',
            'attachment_size': 2048,
            'sender_user_id': 14,
            'sender_name': 'Designer',
            'created_at': '2026-11-05T12:00:00Z',
            'conversation_member': {
              'user_id': 14,
              'name': 'Designer',
              'role': 'designer',
            },
          },
        ],
      },
    );
    final files = await _testService(client).getProjectDirectFiles(
      token: 'test-session-token',
      projectId: '8',
    );

    expect(files, hasLength(1));
    expect(files.single.$1.attachmentName, 'design.jpg');
    expect(files.single.$2.userId, 14);
    final request = client.requests.single as http.Request;
    expect(request.url.path, '/api/projects/8/chat/files');
    expect(_authorizationHeader(request), startsWith('Bearer '));
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
    this.responseText,
    this.responseHeaders = const {},
  });

  final int statusCode;
  final Map<String, dynamic> responseBody;
  final String? responseText;
  final Map<String, String> responseHeaders;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final body = utf8.encode(responseText ?? jsonEncode(responseBody));
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
