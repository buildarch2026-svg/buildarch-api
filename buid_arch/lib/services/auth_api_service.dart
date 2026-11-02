import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/project.dart';
import '../models/project_document.dart';
import '../models/project_invitation.dart';
import '../models/project_message.dart';
import '../models/project_member.dart';
import '../models/project_notification.dart';
import '../models/project_transaction.dart';
import '../models/project_type.dart';
import 'api_configuration.dart';

class AuthApiException implements Exception {
  const AuthApiException(
    this.message, {
    this.statusCode,
    this.retryAfterSeconds,
  });

  final String message;
  final int? statusCode;
  final int? retryAfterSeconds;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

class AuthApiService {
  AuthApiService({
    http.Client? client,
    ApiConfiguration? configuration,
  })  : _client = client ?? http.Client(),
        _configuration = configuration ?? ApiConfiguration.fromEnvironment();

  static final instance = AuthApiService();
  static const _timeout = Duration(seconds: 15);
  static const _uploadTimeout = Duration(minutes: 10);

  final http.Client _client;
  final ApiConfiguration _configuration;

  Uri _apiUri(String path) {
    try {
      return _configuration.resolve(path);
    } on ApiConfigurationException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<void> requestOtp(String phoneNumber) async {
    await _post('/auth/otp/request', {
      'phone_number': _normalizePhoneNumber(phoneNumber),
    });
  }

  Future<void> requestProfilePhoneOtp({
    required String token,
    required String phoneNumber,
  }) async {
    await _post(
      '/user/profile/phone/request',
      {'phone_number': _normalizePhoneNumber(phoneNumber)},
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> verifyProfilePhone({
    required String token,
    required String phoneNumber,
    required String code,
  }) async {
    final response = await _post(
      '/user/profile/phone/verify',
      {
        'phone_number': _normalizePhoneNumber(phoneNumber),
        'code': code,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response['verified'] != true) {
      throw const AuthApiException('The mobile number was not verified.');
    }
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String phoneNumber,
    required String code,
  }) async {
    final response = await _post('/auth/otp/verify', {
      'phone_number': _normalizePhoneNumber(phoneNumber),
      'code': code,
    });

    if (response['verified'] != true) {
      throw const AuthApiException('The verification code was not accepted.');
    }

    return _validatedAuthSession(response);
  }

  Future<Map<String, dynamic>> getCurrentUser({required String token}) async {
    final response = await _get('/user', headers: {
      'Authorization': 'Bearer $token',
    });

    if (response['id'] == null) {
      throw const AuthApiException('The saved session is no longer valid.');
    }

    return response;
  }

  Future<void> logout({required String token}) async {
    await _post(
      '/auth/logout',
      const {},
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<Map<String, dynamic>> updateProfile({
    required String token,
    required String name,
    required String location,
    required String role,
  }) async {
    final response = await _patch('/user/profile', {
      'name': name,
      'location': location,
      'role': role,
    }, headers: {
      'Authorization': 'Bearer $token',
    });

    final user = response['user'];
    if (user is Map<String, dynamic>) return user;
    if (user is Map) return Map<String, dynamic>.from(user);
    throw const AuthApiException('The profile response was invalid.');
  }

  Future<List<Project>> getProjects({required String token}) async {
    final response = await _get('/projects', headers: {
      'Authorization': 'Bearer $token',
    });
    final projects = response['projects'];
    if (projects is! List) {
      throw const AuthApiException('The projects response was invalid.');
    }

    try {
      return projects.map((project) {
        if (project is Map<String, dynamic>) {
          return Project.fromJson(project);
        }
        if (project is Map) {
          return Project.fromJson(Map<String, dynamic>.from(project));
        }
        throw const FormatException('The project response was invalid.');
      }).toList();
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<ProjectNotificationInbox> getNotifications({
    required String token,
  }) async {
    final response = await _get(
      '/notifications',
      headers: {'Authorization': 'Bearer $token'},
    );
    final notifications = response['notifications'];
    final unreadCount = response['unread_count'];
    if (notifications is! List || unreadCount is! num) {
      throw const AuthApiException('The notifications response was invalid.');
    }
    try {
      return ProjectNotificationInbox(
        notifications: notifications.map((notification) {
          if (notification is Map) {
            return ProjectNotification.fromJson(
              Map<String, dynamic>.from(notification),
            );
          }
          throw const FormatException('The notification response was invalid.');
        }).toList(),
        unreadCount: unreadCount.toInt(),
      );
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<void> markNotificationRead({
    required String token,
    required String notificationId,
  }) async {
    await _post(
      '/notifications/${Uri.encodeComponent(notificationId)}/read',
      const {},
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<List<ProjectInvitation>> getProjectInvitations({
    required String token,
    required String projectId,
  }) async {
    final response = await _get(
      '/projects/$projectId/invitations',
      headers: {'Authorization': 'Bearer $token'},
    );
    final invitations = response['invitations'];
    if (invitations is! List) {
      throw const AuthApiException('The invitations response was invalid.');
    }
    try {
      return invitations.map((invitation) {
        if (invitation is Map) {
          return ProjectInvitation.fromJson(
            Map<String, dynamic>.from(invitation),
          );
        }
        throw const FormatException('The invitation response was invalid.');
      }).toList();
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<List<ProjectTransaction>> getProjectTransactions({
    required String token,
    required String projectId,
  }) async {
    final response = await _get(
      '/projects/$projectId/transactions',
      headers: {'Authorization': 'Bearer $token'},
    );
    final transactions = response['transactions'];
    if (transactions is! List) {
      throw const AuthApiException(
          'The project transactions response was invalid.');
    }

    try {
      return transactions.map((transaction) {
        if (transaction is Map) {
          return ProjectTransaction.fromJson(
              Map<String, dynamic>.from(transaction));
        }
        throw const FormatException(
            'The project transaction response was invalid.');
      }).toList();
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<ProjectTransaction> createProjectTransaction({
    required String token,
    required String projectId,
    required String payeeName,
    required String payeeType,
    required double amount,
    required String currency,
    required String status,
    required String paymentMethod,
    required String paymentType,
    String? payeeVpa,
    String? attemptId,
    String? qrPayload,
    String? description,
    String? category,
    String? providerReference,
  }) async {
    final response = await _post(
      '/projects/$projectId/transactions',
      {
        'payee_name': payeeName,
        'payee_type': payeeType,
        if (payeeVpa != null) 'payee_vpa': payeeVpa,
        'amount': amount,
        'currency': currency,
        'status': status,
        'payment_method': paymentMethod,
        'payment_type': paymentType,
        if (attemptId != null) 'attempt_id': attemptId,
        if (qrPayload != null) 'qr_payload': qrPayload,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (category != null && category.isNotEmpty) 'category': category,
        if (providerReference != null && providerReference.isNotEmpty)
          'provider_reference': providerReference,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    final transaction = response['transaction'];
    if (transaction is! Map) {
      throw const AuthApiException(
          'The project transaction response was invalid.');
    }
    try {
      return ProjectTransaction.fromJson(
          Map<String, dynamic>.from(transaction));
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<ProjectTransaction> updateProjectTransactionStatus({
    required String token,
    required String projectId,
    required String transactionId,
    required String status,
    String? providerReference,
  }) async {
    final response = await _patch(
      '/projects/$projectId/transactions/$transactionId',
      {
        'status': status,
        if (providerReference != null) 'provider_reference': providerReference,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    final transaction = response['transaction'];
    if (transaction is! Map) {
      throw const AuthApiException(
          'The project transaction response was invalid.');
    }
    try {
      return ProjectTransaction.fromJson(
          Map<String, dynamic>.from(transaction));
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<List<ProjectMember>> getProjectMembers({
    required String token,
    required String projectId,
  }) async {
    final response = await _get(
      '/projects/$projectId/members',
      headers: {'Authorization': 'Bearer $token'},
    );
    final owner = response['owner'];
    final members = response['members'];
    if (owner is! Map || members is! List) {
      throw const AuthApiException('The project members response was invalid.');
    }

    try {
      final ownerMember = ProjectMember.fromJson(
        Map<String, dynamic>.from(owner),
      );
      return [
        ownerMember,
        ...members.map((member) {
          if (member is Map) {
            return ProjectMember.fromJson(Map<String, dynamic>.from(member));
          }
          throw const FormatException(
            'The project members response was invalid.',
          );
        }),
      ];
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<List<ProjectMessage>> getDirectMessages({
    required String token,
    required String projectId,
    required int memberUserId,
    int afterId = 0,
  }) async {
    final response = await _get(
      '/projects/$projectId/members/$memberUserId/messages'
      '?after_id=$afterId',
      headers: {'Authorization': 'Bearer $token'},
    );
    final messages = response['messages'];
    if (messages is! List) {
      throw const AuthApiException('The chat response was invalid.');
    }
    try {
      return messages.map((message) {
        if (message is Map) {
          return ProjectMessage.fromJson(Map<String, dynamic>.from(message));
        }
        throw const FormatException('The chat message response was invalid.');
      }).toList();
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<List<ProjectMessage>> getProjectGroupMessages({
    required String token,
    required String projectId,
    int afterId = 0,
  }) async {
    final response = await _get(
      '/projects/$projectId/group-chat?after_id=$afterId',
      headers: {'Authorization': 'Bearer $token'},
    );
    final messages = response['messages'];
    if (messages is! List) {
      throw const AuthApiException('The group chat response was invalid.');
    }
    try {
      return messages.map((message) {
        if (message is Map) {
          return ProjectMessage.fromJson(Map<String, dynamic>.from(message));
        }
        throw const FormatException(
          'The group chat message response was invalid.',
        );
      }).toList();
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<List<ProjectMessage>> getProjectGroupFiles({
    required String token,
    required String projectId,
  }) async {
    final response = await _get(
      '/projects/$projectId/group-chat/files',
      headers: {'Authorization': 'Bearer $token'},
    );
    final files = response['files'];
    if (files is! List) {
      throw const AuthApiException('The project files response was invalid.');
    }
    try {
      return files.map((file) {
        if (file is Map) {
          return ProjectMessage.fromJson(Map<String, dynamic>.from(file));
        }
        throw const FormatException('The project file response was invalid.');
      }).toList();
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<ProjectMessage> sendProjectGroupVoice({
    required String token,
    required String projectId,
    required File file,
  }) {
    return sendProjectGroupAttachment(
      token: token,
      projectId: projectId,
      file: XFile(file.path),
      messageType: 'voice',
    );
  }

  Future<ProjectMessage> sendProjectGroupAttachment({
    required String token,
    required String projectId,
    required XFile file,
    required String messageType,
  }) async {
    final size = await file.length();
    final uri = _apiUri('projects/$projectId/group-chat/attachments');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      })
      ..fields['message_type'] = messageType
      ..files.add(
        http.MultipartFile(
          'file',
          file.openRead(),
          size,
          filename: file.name,
        ),
      );

    try {
      final streamedResponse =
          await _client.send(request).timeout(_uploadTimeout);
      final response = await http.Response.fromStream(streamedResponse)
          .timeout(_uploadTimeout);
      final message = _decodeResponse(response)['message'];
      if (message is Map) {
        try {
          return ProjectMessage.fromJson(Map<String, dynamic>.from(message));
        } on FormatException catch (error) {
          throw AuthApiException(error.message);
        }
      }
      throw const AuthApiException('The attachment response was invalid.');
    } on SocketException {
      throw const AuthApiException(
        'Cannot reach the API. Check that Laravel is running and the API URL is correct.',
      );
    } on TimeoutException {
      throw const AuthApiException('The upload timed out. Try again.');
    } on http.ClientException {
      throw const AuthApiException(
        'Could not connect to the API. Check the device network and API URL.',
      );
    }
  }

  Future<ProjectMessage> sendProjectGroupText({
    required String token,
    required String projectId,
    required String body,
  }) async {
    final response = await _post(
      '/projects/$projectId/group-chat/messages',
      {'body': body},
      headers: {'Authorization': 'Bearer $token'},
    );
    final message = response['message'];
    if (message is! Map) {
      throw const AuthApiException('The sent message response was invalid.');
    }
    try {
      return ProjectMessage.fromJson(Map<String, dynamic>.from(message));
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<File> downloadProjectGroupVoice({
    required String token,
    required String projectId,
    required int messageId,
  }) {
    final uri = _apiUri(
      'projects/$projectId/group-chat/attachments/$messageId',
    );
    return _downloadToTemporaryFile(uri, token);
  }

  Future<ProjectMessage> sendDirectMessage({
    required String token,
    required String projectId,
    required int memberUserId,
    required String body,
  }) async {
    final response = await _post(
      '/projects/$projectId/members/$memberUserId/messages',
      {'body': body},
      headers: {'Authorization': 'Bearer $token'},
    );
    final message = response['message'];
    if (message is! Map) {
      throw const AuthApiException('The sent message response was invalid.');
    }
    try {
      return ProjectMessage.fromJson(Map<String, dynamic>.from(message));
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<ProjectMessage> sendDirectAttachment({
    required String token,
    required String projectId,
    required int memberUserId,
    required String messageType,
    required String fileName,
    required int fileSize,
    required Stream<List<int>> fileBytes,
  }) async {
    final uri = _apiUri(
      'projects/$projectId/members/$memberUserId/messages/attachments',
    );
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      })
      ..fields['message_type'] = messageType
      ..files.add(
        http.MultipartFile('file', fileBytes, fileSize, filename: fileName),
      );

    try {
      final streamedResponse =
          await _client.send(request).timeout(_uploadTimeout);
      final response = await http.Response.fromStream(streamedResponse)
          .timeout(_uploadTimeout);
      final message = _decodeResponse(response)['message'];
      if (message is Map) {
        try {
          return ProjectMessage.fromJson(Map<String, dynamic>.from(message));
        } on FormatException catch (error) {
          throw AuthApiException(error.message);
        }
      }
      throw const AuthApiException('The attachment response was invalid.');
    } on SocketException {
      throw const AuthApiException(
        'Cannot reach the API. Check that Laravel is running and the API URL is correct.',
      );
    } on TimeoutException {
      throw const AuthApiException('The upload timed out. Try again.');
    } on http.ClientException {
      throw const AuthApiException(
        'Could not connect to the API. Check the device network and API URL.',
      );
    }
  }

  Future<List<ProjectDocument>> getProjectDocuments({
    required String token,
    required String projectId,
  }) async {
    final response = await _get(
      '/projects/$projectId/documents',
      headers: {'Authorization': 'Bearer $token'},
    );
    final documents = response['documents'];
    if (documents is! List) {
      throw const AuthApiException('The uploaded files response was invalid.');
    }
    try {
      return documents.map((document) {
        if (document is Map) {
          return ProjectDocument.fromJson(Map<String, dynamic>.from(document));
        }
        throw const FormatException('The uploaded file response was invalid.');
      }).toList();
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<ProjectDocument> uploadProjectDocument({
    required String token,
    required String projectId,
    required PlatformFile file,
  }) async {
    final size = await file.length();
    if (size == null) {
      throw const AuthApiException('Could not read the selected file.');
    }
    final uri = _apiUri('projects/$projectId/documents');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      })
      ..files.add(
        http.MultipartFile(
          'file',
          file.readAsByteStream(),
          size,
          filename: file.name,
        ),
      );

    try {
      final streamedResponse =
          await _client.send(request).timeout(_uploadTimeout);
      final response = await http.Response.fromStream(streamedResponse)
          .timeout(_uploadTimeout);
      final document = _decodeResponse(response)['document'];
      if (document is Map) {
        try {
          return ProjectDocument.fromJson(Map<String, dynamic>.from(document));
        } on FormatException catch (error) {
          throw AuthApiException(error.message);
        }
      }
      throw const AuthApiException('The uploaded file response was invalid.');
    } on SocketException {
      throw const AuthApiException(
        'Cannot reach the API. Check that Laravel is running and the API URL is correct.',
      );
    } on TimeoutException {
      throw const AuthApiException('The API request timed out. Try again.');
    } on http.ClientException {
      throw const AuthApiException(
        'Could not connect to the API. Check the device network and API URL.',
      );
    }
  }

  Future<File> downloadProjectDocument({
    required String token,
    required String projectId,
    required int documentId,
  }) async {
    final uri = _apiUri('projects/$projectId/documents/$documentId');
    return _downloadToTemporaryFile(uri, token);
  }

  Future<File> downloadDirectAttachment({
    required String token,
    required String projectId,
    required int memberUserId,
    required int messageId,
  }) {
    final uri = _apiUri(
      'projects/$projectId/members/$memberUserId/messages/$messageId/attachment',
    );
    return _downloadToTemporaryFile(uri, token);
  }

  Future<File> _downloadToTemporaryFile(Uri uri, String token) async {
    late final http.StreamedResponse response;
    try {
      final request = http.Request('GET', uri)
        ..headers.addAll({
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        });
      response = await _client.send(request).timeout(_uploadTimeout);
    } on SocketException {
      throw const AuthApiException(
        'Cannot reach the API. Check that Laravel is running and the API URL is correct.',
      );
    } on TimeoutException {
      throw const AuthApiException('The API request timed out. Try again.');
    } on http.ClientException {
      throw const AuthApiException(
        'Could not connect to the API. Check the device network and API URL.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      try {
        _decodeResponse(
          await http.Response.fromStream(response).timeout(_uploadTimeout),
        );
      } on TimeoutException {
        throw const AuthApiException(
          'The API did not finish its error response. Try again.',
        );
      }
      throw const AuthApiException('The file could not be downloaded.');
    }

    final temporaryDirectory = await getTemporaryDirectory();
    final file = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}'
      'project-download-${DateTime.now().microsecondsSinceEpoch}',
    );
    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream.timeout(_uploadTimeout)) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      return file;
    } on TimeoutException {
      await sink.close();
      await file.delete().catchError((_) => file);
      throw const AuthApiException('The download timed out. Try again.');
    } on SocketException {
      await sink.close();
      await file.delete().catchError((_) => file);
      throw const AuthApiException(
        'The download was interrupted. Check the network and try again.',
      );
    } catch (_) {
      await sink.close();
      await file.delete().catchError((_) => file);
      rethrow;
    }
  }

  Future<ProjectInvitation> createProjectInvitation({
    required String token,
    required String projectId,
    required String inviteeName,
    required String inviteeDesignation,
  }) async {
    final response = await _post(
      '/projects/$projectId/invitations',
      {
        'invitee_name': inviteeName,
        'invitee_designation': inviteeDesignation,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    final invitation = response['invitation'];
    if (invitation is! Map) {
      throw const AuthApiException('The invitation response was invalid.');
    }
    try {
      return ProjectInvitation.fromJson(Map<String, dynamic>.from(invitation));
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<void> revokeProjectInvitation({
    required String token,
    required String projectId,
    required int invitationId,
  }) async {
    await _post(
      '/projects/$projectId/invitations/$invitationId/revoke',
      const {},
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<ProjectInvitationDetails> getInvitationDetails({
    required String token,
    required String invitationToken,
  }) async {
    final response = await _get(
      '/invitations/$invitationToken',
      headers: {'Authorization': 'Bearer $token'},
    );
    try {
      return ProjectInvitationDetails.fromJson(response);
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<void> acceptProjectInvitation({
    required String token,
    required String invitationToken,
  }) async {
    await _post(
      '/invitations/$invitationToken/accept',
      const {},
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> declineProjectInvitation({
    required String token,
    required String invitationToken,
  }) async {
    await _post(
      '/invitations/$invitationToken/decline',
      const {},
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<Project> createProject({
    required String token,
    required String name,
    required String location,
    required ProjectType type,
    double? latitude,
    double? longitude,
    XFile? photo,
  }) async {
    final fields = <String, String>{
      'name': name,
      'location': location,
      'type': type.apiValue,
      if (latitude != null) 'latitude': latitude.toString(),
      if (longitude != null) 'longitude': longitude.toString(),
    };

    if (photo != null) {
      final response = await _postMultipart(
        '/projects',
        fields,
        photo: photo,
        headers: {'Authorization': 'Bearer $token'},
      );
      return _projectFromResponse(response);
    }

    final response = await _post(
      '/projects',
      fields,
      headers: {'Authorization': 'Bearer $token'},
    );

    return _projectFromResponse(response);
  }

  Future<Project> updateProject({
    required String token,
    required String projectId,
    required String name,
    required String location,
    required ProjectType type,
    double? latitude,
    double? longitude,
  }) async {
    final response = await _patch(
      '/projects/$projectId',
      {
        'name': name,
        'location': location,
        'type': type.apiValue,
        'latitude': latitude,
        'longitude': longitude,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    return _projectFromResponse(response);
  }

  Future<Project> archiveProject({
    required String token,
    required String projectId,
  }) async {
    final response = await _post(
      '/projects/$projectId/archive',
      const {},
      headers: {'Authorization': 'Bearer $token'},
    );
    return _projectFromResponse(response);
  }

  Future<Project> deleteProject({
    required String token,
    required String projectId,
  }) async {
    final response = await _delete(
      '/projects/$projectId',
      headers: {'Authorization': 'Bearer $token'},
    );
    return _projectFromResponse(response);
  }

  Future<Project> restoreProject({
    required String token,
    required String projectId,
  }) async {
    final response = await _post(
      '/projects/$projectId/restore',
      const {},
      headers: {'Authorization': 'Bearer $token'},
    );
    return _projectFromResponse(response);
  }

  Future<void> removeProjectMember({
    required String token,
    required String projectId,
    required int memberUserId,
  }) async {
    await _delete(
      '/projects/$projectId/members/$memberUserId',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<Project> uploadProjectPhoto({
    required String token,
    required String projectId,
    required XFile photo,
  }) async {
    final response = await _postMultipart(
      '/projects/$projectId/photo',
      const {},
      photo: photo,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _projectFromResponse(response);
  }

  Project _projectFromResponse(Map<String, dynamic> response) {
    final project = response['project'];
    if (project is Map<String, dynamic>) {
      try {
        return Project.fromJson(project);
      } on FormatException catch (error) {
        throw AuthApiException(error.message);
      }
    }
    if (project is Map) {
      try {
        return Project.fromJson(Map<String, dynamic>.from(project));
      } on FormatException catch (error) {
        throw AuthApiException(error.message);
      }
    }
    throw const AuthApiException('The project response was invalid.');
  }

  Future<Map<String, dynamic>> _postMultipart(
    String path,
    Map<String, String> fields, {
    required XFile photo,
    Map<String, String> headers = const {},
  }) async {
    final uri = _apiUri(path);
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({'Accept': 'application/json', ...headers})
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes(
          'photo',
          await photo.readAsBytes(),
          filename: photo.name,
        ),
      );

    try {
      final streamedResponse = await _client.send(request).timeout(_timeout);
      final response =
          await http.Response.fromStream(streamedResponse).timeout(_timeout);
      return _decodeResponse(response);
    } on SocketException {
      throw const AuthApiException(
        'Cannot reach the API. Check that Laravel is running and the API URL is correct.',
      );
    } on TimeoutException {
      throw const AuthApiException('The API request timed out. Try again.');
    } on http.ClientException {
      throw const AuthApiException(
        'Could not connect to the API. Check the device network and API URL.',
      );
    }
  }

  Future<Map<String, dynamic>> signInWithGoogle({
    required String idToken,
  }) async {
    final response = await _post('/auth/google', {'id_token': idToken});

    if (response['verified'] != true) {
      throw const AuthApiException('Google sign-in was not accepted.');
    }

    return _validatedAuthSession(response);
  }

  Map<String, dynamic> _validatedAuthSession(Map<String, dynamic> response) {
    final token = response['token'];
    final rawUser = response['user'];
    final userId = rawUser is Map ? rawUser['id'] : null;
    if (token is! String ||
        token.trim().isEmpty ||
        rawUser is! Map ||
        userId is! num ||
        userId <= 0 ||
        userId != userId.toInt() ||
        rawUser['profile_complete'] is! bool) {
      throw const AuthApiException(
        'The sign-in response was invalid. Please try again.',
      );
    }

    try {
      return {
        ...response,
        'token': token.trim(),
        'user': Map<String, dynamic>.from(rawUser),
      };
    } on TypeError {
      throw const AuthApiException(
        'The sign-in response was invalid. Please try again.',
      );
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) async {
    final uri = _apiUri(path);
    late final http.Response response;

    try {
      response = await _client
          .post(
            uri,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              ...headers,
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on SocketException {
      throw const AuthApiException(
        'Cannot reach the API. Check that Laravel is running and the API URL is correct.',
      );
    } on TimeoutException {
      throw const AuthApiException('The API request timed out. Try again.');
    } on http.ClientException {
      throw const AuthApiException(
        'Could not connect to the API. Check the device network and API URL.',
      );
    }

    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    final uri = _apiUri(path);
    late final http.Response response;

    try {
      response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/json',
          ...headers,
        },
      ).timeout(_timeout);
    } on SocketException {
      throw const AuthApiException(
        'Cannot reach the API. Check that Laravel is running and the API URL is correct.',
      );
    } on TimeoutException {
      throw const AuthApiException('The API request timed out. Try again.');
    } on http.ClientException {
      throw const AuthApiException(
        'Could not connect to the API. Check the device network and API URL.',
      );
    }

    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _patch(
    String path,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) async {
    final uri = _apiUri(path);
    late final http.Response response;

    try {
      response = await _client
          .patch(
            uri,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              ...headers,
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on SocketException {
      throw const AuthApiException(
        'Cannot reach the API. Check that Laravel is running and the API URL is correct.',
      );
    } on TimeoutException {
      throw const AuthApiException('The API request timed out. Try again.');
    } on http.ClientException {
      throw const AuthApiException(
        'Could not connect to the API. Check the device network and API URL.',
      );
    }

    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _delete(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    final uri = _apiUri(path);
    late final http.Response response;

    try {
      response = await _client.delete(
        uri,
        headers: {
          'Accept': 'application/json',
          ...headers,
        },
      ).timeout(_timeout);
    } on SocketException {
      throw const AuthApiException(
        'Cannot reach the API. Check that Laravel is running and the API URL is correct.',
      );
    } on TimeoutException {
      throw const AuthApiException('The API request timed out. Try again.');
    } on http.ClientException {
      throw const AuthApiException(
        'Could not connect to the API. Check the device network and API URL.',
      );
    }

    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      } else if (decoded is Map) {
        data = Map<String, dynamic>.from(decoded);
      }
    } on FormatException {
      // Keep the response as an HTTP error if Laravel returned non-JSON output.
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthApiException(
        _messageFrom(data),
        statusCode: response.statusCode,
        retryAfterSeconds: int.tryParse(response.headers['retry-after'] ?? ''),
      );
    }

    return data;
  }

  String _normalizePhoneNumber(String phoneNumber) {
    final normalized = phoneNumber.replaceAll(RegExp(r'[\s()-]'), '');
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalized)) {
      throw const AuthApiException('Enter a valid international phone number.');
    }
    return normalized;
  }

  String _messageFrom(Map<String, dynamic> data) {
    final errors = data['errors'];
    if (errors is Map<String, dynamic>) {
      for (final value in errors.values) {
        if (value is List && value.isNotEmpty) return value.first.toString();
      }
    }

    final message = data['message'];
    if (message is String && message.isNotEmpty) return message;
    return 'The request failed. Please try again.';
  }
}
