import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/project.dart';
import '../models/project_chat_conversation.dart';
import '../models/community.dart';
import '../models/job_portal.dart';
import '../models/project_document.dart';
import '../models/project_invitation.dart';
import '../models/project_member.dart';
import '../models/project_message.dart';
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

  Future<JobPortalDashboard> getJobPortalDashboard({
    required String token,
  }) async {
    final response = await _get(
      '/jobs/dashboard',
      headers: {'Authorization': 'Bearer $token'},
    );
    try {
      return JobPortalDashboard.fromJson(response);
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<List<JobPortalCategory>> getJobPortalCategories({
    required String token,
  }) async {
    final response = await _get(
      '/jobs/categories',
      headers: {'Authorization': 'Bearer $token'},
    );
    final raw = response['categories'];
    if (raw is! List) {
      throw const AuthApiException('The job categories response was invalid.');
    }
    try {
      return raw.map((value) {
        if (value is! Map) {
          throw const FormatException('The job category was invalid.');
        }
        return JobPortalCategory.fromJson(Map<String, dynamic>.from(value));
      }).toList(growable: false);
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<JobPortalPage<ConstructionJob>> getConstructionJobs({
    required String token,
    int page = 1,
    String? query,
    String? category,
    String? employmentType,
    String? location,
    double? latitude,
    double? longitude,
    int? distanceKm,
    double? minSalary,
    double? maxSalary,
    String? experience,
    String sort = 'latest',
  }) async {
    final parameters = <String, String>{'page': '$page'};
    if (query?.trim().isNotEmpty == true) parameters['q'] = query!.trim();
    if (category != null) parameters['category'] = category;
    if (employmentType != null) parameters['employment_type'] = employmentType;
    if (minSalary != null) parameters['min_salary'] = '$minSalary';
    if (maxSalary != null) parameters['max_salary'] = '$maxSalary';
    if (experience?.trim().isNotEmpty == true) {
      parameters['experience'] = experience!.trim();
    }
    parameters['sort'] = sort;
    if (location?.trim().isNotEmpty == true) {
      parameters['location'] = location!.trim();
    }
    if (latitude != null && longitude != null) {
      parameters['latitude'] = '$latitude';
      parameters['longitude'] = '$longitude';
      if (distanceKm != null) parameters['distance_km'] = '$distanceKm';
    }
    final response = await _get(
      '/jobs?${Uri(queryParameters: parameters).query}',
      headers: {'Authorization': 'Bearer $token'},
    );
    try {
      return JobPortalPage<ConstructionJob>.fromJson(
        response,
        'jobs',
        ConstructionJob.fromJson,
      );
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<ConstructionJob> getConstructionJob({
    required String token,
    required int jobId,
  }) async {
    final response = await _get(
      '/jobs/$jobId',
      headers: {'Authorization': 'Bearer $token'},
    );
    return _constructionJobFromResponse(response);
  }

  Future<ConstructionJob> createConstructionJob({
    required String token,
    required Map<String, dynamic> fields,
  }) async {
    final response = await _post(
      '/jobs',
      fields,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _constructionJobFromResponse(response);
  }

  Future<ConstructionJob> updateConstructionJob({
    required String token,
    required int jobId,
    required Map<String, dynamic> fields,
  }) async {
    final response = await _patch(
      '/jobs/$jobId',
      fields,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _constructionJobFromResponse(response);
  }

  Future<void> updateConstructionJobStatus({
    required String token,
    required int jobId,
    required String status,
  }) async {
    await _put(
      '/jobs/$jobId/status',
      {'status': status},
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> deleteConstructionJob({
    required String token,
    required int jobId,
  }) async {
    await _delete(
      '/jobs/$jobId',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<JobPortalEmployerProfile?> getEmployerProfile({
    required String token,
  }) async {
    final response = await _get(
      '/jobs/employer-profile',
      headers: {'Authorization': 'Bearer $token'},
    );
    final profile = response['profile'];
    if (profile == null) return null;
    if (profile is! Map) {
      throw const AuthApiException(
          'The employer profile response was invalid.');
    }
    try {
      return JobPortalEmployerProfile.fromJson(
        Map<String, dynamic>.from(profile),
      );
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<JobPortalEmployerProfile> saveEmployerProfile({
    required String token,
    required Map<String, dynamic> fields,
    XFile? companyLogo,
  }) async {
    final response = await _postJobMultipart(
      '/jobs/employer-profile',
      token: token,
      fields: fields,
      files: {if (companyLogo != null) 'company_logo': companyLogo},
    );
    final profile = response['profile'];
    if (profile is! Map) {
      throw const AuthApiException(
          'The employer profile response was invalid.');
    }
    try {
      return JobPortalEmployerProfile.fromJson(
        Map<String, dynamic>.from(profile),
      );
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<JobPortalSeekerProfile?> getJobSeekerProfile({
    required String token,
  }) async {
    final response = await _get(
      '/jobs/job-seeker-profile',
      headers: {'Authorization': 'Bearer $token'},
    );
    final profile = response['profile'];
    if (profile == null) return null;
    if (profile is! Map) {
      throw const AuthApiException(
          'The job seeker profile response was invalid.');
    }
    try {
      return JobPortalSeekerProfile.fromJson(
        Map<String, dynamic>.from(profile),
      );
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<JobPortalSeekerProfile> saveJobSeekerProfile({
    required String token,
    required Map<String, dynamic> fields,
    XFile? profileImage,
    XFile? resume,
  }) async {
    final response = await _postJobMultipart(
      '/jobs/job-seeker-profile',
      token: token,
      fields: fields,
      files: {
        if (profileImage != null) 'profile_image': profileImage,
        if (resume != null) 'resume': resume,
      },
    );
    final profile = response['profile'];
    if (profile is! Map) {
      throw const AuthApiException(
          'The job seeker profile response was invalid.');
    }
    try {
      return JobPortalSeekerProfile.fromJson(
        Map<String, dynamic>.from(profile),
      );
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<void> saveConstructionJob({
    required String token,
    required int jobId,
  }) async {
    await _put(
      '/jobs/$jobId/saved',
      const {},
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> unsaveConstructionJob({
    required String token,
    required int jobId,
  }) async {
    await _delete(
      '/jobs/$jobId/saved',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<JobPortalApplication> applyForConstructionJob({
    required String token,
    required int jobId,
    String? coverLetter,
    XFile? resume,
  }) async {
    final fields = <String, dynamic>{
      if (coverLetter?.trim().isNotEmpty == true)
        'cover_letter': coverLetter!.trim(),
    };
    final response = resume == null
        ? await _post(
            '/jobs/$jobId/applications',
            fields,
            headers: {'Authorization': 'Bearer $token'},
          )
        : await _postJobMultipart(
            '/jobs/$jobId/applications',
            token: token,
            fields: fields,
            files: {'resume': resume},
          );
    final application = response['application'];
    if (application is! Map) {
      throw const AuthApiException('The application response was invalid.');
    }
    try {
      return JobPortalApplication.fromJson(
        Map<String, dynamic>.from(application),
      );
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<JobPortalPage<JobPortalApplication>> getMyJobApplications({
    required String token,
    int page = 1,
  }) async {
    final response = await _get(
      '/jobs/applications?page=$page',
      headers: {'Authorization': 'Bearer $token'},
    );
    try {
      return JobPortalPage<JobPortalApplication>.fromJson(
        response,
        'applications',
        JobPortalApplication.fromJson,
      );
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<JobPortalPage<ConstructionJob>> getMyJobPostings({
    required String token,
    int page = 1,
  }) async {
    final response = await _get(
      '/jobs/my-postings?page=$page',
      headers: {'Authorization': 'Bearer $token'},
    );
    try {
      return JobPortalPage<ConstructionJob>.fromJson(
        response,
        'jobs',
        ConstructionJob.fromJson,
      );
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<JobPortalPage<JobPortalApplication>> getJobApplicants({
    required String token,
    required int jobId,
    int page = 1,
  }) async {
    final response = await _get(
      '/jobs/$jobId/applications?page=$page',
      headers: {'Authorization': 'Bearer $token'},
    );
    try {
      return JobPortalPage<JobPortalApplication>.fromJson(
        response,
        'applications',
        JobPortalApplication.fromJson,
      );
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<void> updateJobApplication({
    required String token,
    required int applicationId,
    required String status,
    String? interviewAt,
    String? employerNote,
  }) async {
    await _patch(
      '/jobs/applications/$applicationId',
      {
        'status': status,
        if (interviewAt != null) 'interview_at': interviewAt,
        if (employerNote != null) 'employer_note': employerNote,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> withdrawJobApplication({
    required String token,
    required int applicationId,
  }) async {
    await _post(
      '/jobs/applications/$applicationId/withdraw',
      const {},
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<XFile> downloadJobApplicationResume({
    required String token,
    required int applicationId,
    required String fileName,
  }) async {
    late final http.Response response;
    try {
      response = await _client.get(
        _apiUri('/jobs/applications/$applicationId/resume'),
        headers: {
          'Accept': '*/*',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_uploadTimeout);
    } on SocketException {
      throw const AuthApiException(
        'Cannot reach the API. Check that Laravel is running and the API URL is correct.',
      );
    } on TimeoutException {
      throw const AuthApiException('The resume download timed out. Try again.');
    } on http.ClientException {
      throw const AuthApiException(
        'Could not connect to the API. Check the device network and API URL.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decodeResponse(response);
      throw const AuthApiException(
          'The resume download could not be completed.');
    }
    return XFile.fromData(
      response.bodyBytes,
      name: fileName,
      mimeType: response.headers['content-type'],
    );
  }

  Future<void> reportConstructionJob({
    required String token,
    required int jobId,
    required String reason,
    String? details,
  }) async {
    await _post(
      '/jobs/$jobId/reports',
      {
        'reason': reason,
        if (details?.trim().isNotEmpty == true) 'details': details!.trim()
      },
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  ConstructionJob _constructionJobFromResponse(
    Map<String, dynamic> response,
  ) {
    final job = response['job'];
    if (job is! Map) {
      throw const AuthApiException('The job response was invalid.');
    }
    try {
      return ConstructionJob.fromJson(Map<String, dynamic>.from(job));
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<Map<String, dynamic>> _postJobMultipart(
    String path, {
    required String token,
    required Map<String, dynamic> fields,
    Map<String, XFile> files = const {},
  }) async {
    final request = http.MultipartRequest('POST', _apiUri(path))
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      });
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is Iterable) {
        if (value.isEmpty) {
          request.fields[entry.key] = '[]';
          continue;
        }
        var index = 0;
        for (final item in value) {
          request.fields['${entry.key}[$index]'] = '$item';
          index++;
        }
      } else {
        request.fields[entry.key] = '$value';
      }
    }
    for (final entry in files.entries) {
      request.files.add(
        http.MultipartFile.fromBytes(
          entry.key,
          await entry.value.readAsBytes(),
          filename: entry.value.name,
        ),
      );
    }
    try {
      final streamed = await _client.send(request).timeout(_uploadTimeout);
      final response =
          await http.Response.fromStream(streamed).timeout(_uploadTimeout);
      return _decodeResponse(response);
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

  Future<CommunityProfile?> getCommunityProfile({required String token}) async {
    final response = await _get(
      '/community/profile',
      headers: {'Authorization': 'Bearer $token'},
    );
    final profile = response['profile'];
    if (profile == null) return null;
    if (profile is! Map) {
      throw const AuthApiException(
          'The Community profile response was invalid.');
    }
    try {
      return CommunityProfile.fromJson(Map<String, dynamic>.from(profile));
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<CommunityProfile> registerCommunityProfile({
    required String token,
    required String displayName,
    String? profession,
    String? location,
    String? otherProfession,
    String? bio,
    XFile? profileImage,
  }) async {
    final response = await _communityMultipartPost(
      '/community/profile',
      token: token,
      fields: {
        'display_name': displayName,
        'guidelines_accepted': '1',
        if (profession != null) 'profession': profession,
        if (location != null && location.isNotEmpty) 'location': location,
        if (otherProfession != null) 'other_profession': otherProfession,
        if (bio != null && bio.isNotEmpty) 'bio': bio,
      },
      image: profileImage,
      imageField: 'profile_image',
    );
    return _communityProfileFromResponse(response);
  }

  Future<CommunityProfile> updateCommunityProfile({
    required String token,
    required String displayName,
    required String? profession,
    String? location,
    String? otherProfession,
    String? bio,
    double? latitude,
    double? longitude,
    String? trade,
    List<String>? skills,
    int? experienceYears,
    String? preferredLocation,
    double? preferredLatitude,
    double? preferredLongitude,
    List<int>? preferredCategories,
    int? preferredRadiusKm,
    bool? jobNotificationsEnabled,
  }) async {
    final response = await _patch(
      '/community/profile',
      {
        'display_name': displayName,
        'profession': profession,
        'location': location,
        'other_profession': profession == 'Other' ? otherProfession : null,
        'bio': bio,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'trade': trade,
        if (skills != null) 'skills': skills,
        'experience_years': experienceYears,
        'preferred_location': preferredLocation,
        if (preferredLatitude != null) 'preferred_latitude': preferredLatitude,
        if (preferredLongitude != null)
          'preferred_longitude': preferredLongitude,
        if (preferredCategories != null)
          'preferred_categories': preferredCategories,
        if (preferredRadiusKm != null) 'preferred_radius_km': preferredRadiusKm,
        if (jobNotificationsEnabled != null)
          'job_notifications_enabled': jobNotificationsEnabled,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    return _communityProfileFromResponse(response);
  }

  Future<CommunityProfile> updateCommunityProfileImage({
    required String token,
    required XFile image,
  }) async {
    final response = await _communityMultipartPost(
      '/community/profile/image',
      token: token,
      fields: const {},
      image: image,
      imageField: 'profile_image',
    );
    return _communityProfileFromResponse(response);
  }

  Future<CommunityProfile> removeCommunityProfileImage({
    required String token,
  }) async {
    final response = await _delete(
      '/community/profile/image',
      headers: {'Authorization': 'Bearer $token'},
    );
    return _communityProfileFromResponse(response);
  }

  Future<List<CommunityCategory>> getCommunityCategories({
    required String token,
  }) async {
    final response = await _get(
      '/community/categories',
      headers: {'Authorization': 'Bearer $token'},
    );
    final categoriesJson = response['categories'];
    if (categoriesJson is! List) {
      throw const AuthApiException(
          'The Community categories response was invalid.');
    }
    try {
      return categoriesJson.map((item) {
        if (item is Map) {
          return CommunityCategory.fromJson(
            Map<String, dynamic>.from(item),
          );
        }
        throw const FormatException('The Community category was invalid.');
      }).toList();
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<({List<CommunityCategory> categories, CommunityPost? post})>
      getCommunityPreview({required String token}) async {
    final results = await Future.wait([
      _get('/community/preview', headers: {'Authorization': 'Bearer $token'}),
      _get('/community/categories',
          headers: {'Authorization': 'Bearer $token'}),
    ]);
    final postJson = results[0]['post'];
    final categoriesJson = results[1]['categories'];
    if (categoriesJson is! List) {
      throw const AuthApiException(
          'The Community categories response was invalid.');
    }
    try {
      final categories = categoriesJson.map((item) {
        if (item is Map) {
          return CommunityCategory.fromJson(
            Map<String, dynamic>.from(item),
          );
        }
        throw const FormatException('The Community category was invalid.');
      }).toList();
      return (
        categories: categories,
        post: postJson is Map
            ? CommunityPost.fromJson(Map<String, dynamic>.from(postJson))
            : null,
      );
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<
      ({
        CommunityPage<CommunityPost> page,
        List<CommunityCategory> categories
      })> getCommunityFeed({
    required String token,
    int page = 1,
    String? category,
  }) async {
    final query = <String, String>{'page': '$page'};
    if (category != null) query['category'] = category;
    final response = await _get(
      '/community/feed?${Uri(queryParameters: query).query}',
      headers: {'Authorization': 'Bearer $token'},
    );
    final categoriesJson = response['categories'];
    if (categoriesJson is! List) {
      throw const AuthApiException(
          'The Community categories response was invalid.');
    }
    try {
      return (
        page: CommunityPage<CommunityPost>.fromJson(
          response,
          'posts',
          CommunityPost.fromJson,
        ),
        categories: categoriesJson.map((item) {
          if (item is Map) {
            return CommunityCategory.fromJson(
              Map<String, dynamic>.from(item),
            );
          }
          throw const FormatException('The Community category was invalid.');
        }).toList(),
      );
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<CommunityPost> createCommunityPost({
    required String token,
    required String content,
    int? categoryId,
    List<XFile> images = const [],
  }) async {
    final response = await _communityMultipartPost(
      '/community/posts',
      token: token,
      fields: {
        'content': content,
        if (categoryId != null) 'category_id': '$categoryId',
      },
      images: images,
    );
    return _communityPostFromResponse(response);
  }

  Future<CommunityPost> updateCommunityPost({
    required String token,
    required int postId,
    required String content,
    int? categoryId,
    XFile? image,
    bool removeImage = false,
  }) async {
    final response = await _communityMultipartPost(
      '/community/posts/$postId',
      token: token,
      fields: {
        'content': content,
        if (categoryId != null) 'category_id': '$categoryId',
        if (removeImage) 'remove_image': '1',
      },
      image: image,
      imageField: 'image',
    );
    return _communityPostFromResponse(response);
  }

  Future<void> deleteCommunityPost({
    required String token,
    required int postId,
  }) async {
    await _delete(
      '/community/posts/$postId',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<({bool liked, int likesCount})> toggleCommunityLike({
    required String token,
    required int postId,
  }) async {
    final response = await _put(
      '/community/posts/$postId/like',
      const {},
      headers: {'Authorization': 'Bearer $token'},
    );
    final liked = response['liked'];
    final likesCount = response['likes_count'];
    if (liked is! bool || likesCount is! num) {
      throw const AuthApiException('The Community like response was invalid.');
    }
    return (liked: liked, likesCount: likesCount.toInt());
  }

  Future<CommunityPage<CommunityComment>> getCommunityComments({
    required String token,
    required int postId,
    int page = 1,
  }) async {
    final response = await _get(
      '/community/posts/$postId/comments?page=$page',
      headers: {'Authorization': 'Bearer $token'},
    );
    try {
      return CommunityPage<CommunityComment>.fromJson(
        response,
        'comments',
        CommunityComment.fromJson,
      );
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<CommunityComment> createCommunityComment({
    required String token,
    required int postId,
    required String content,
    int? parentCommentId,
  }) async {
    final response = await _post(
      '/community/posts/$postId/comments',
      {
        'content': content,
        if (parentCommentId != null) 'parent_comment_id': parentCommentId,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    final comment = response['comment'];
    if (comment is! Map) {
      throw const AuthApiException(
          'The Community comment response was invalid.');
    }
    try {
      return CommunityComment.fromJson(Map<String, dynamic>.from(comment));
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<void> deleteCommunityComment({
    required String token,
    required int postId,
    required int commentId,
  }) async {
    await _delete(
      '/community/posts/$postId/comments/$commentId',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> reportCommunityContent({
    required String token,
    required String targetType,
    required int targetId,
    required String reason,
    String? details,
  }) async {
    await _post(
      '/community/reports',
      {
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
        if (details != null && details.isNotEmpty) 'details': details,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<CommunityProfile> getCommunityMemberProfile({
    required String token,
    required int profileId,
  }) async {
    final response = await _get(
      '/community/profiles/$profileId',
      headers: {'Authorization': 'Bearer $token'},
    );
    return _communityProfileFromResponse(response);
  }

  Future<CommunityContactStatus> getCommunityContactStatus({
    required String token,
    required int userId,
  }) async {
    final response = await _get(
      '/community/members/$userId/contact-status',
      headers: {'Authorization': 'Bearer $token'},
    );
    try {
      return CommunityContactStatus.fromJson(response);
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<CommunityContactRequest> sendCommunityContactRequest({
    required String token,
    required int receiverId,
  }) async {
    final response = await _post(
      '/community/contact-requests',
      {'receiver_id': receiverId},
      headers: {'Authorization': 'Bearer $token'},
    );
    return _communityContactRequestFromResponse(response);
  }

  Future<List<CommunityContactRequest>> getCommunityContactRequests({
    required String token,
    String direction = 'received',
  }) async {
    final response = await _get(
      '/community/contact-requests/$direction',
      headers: {'Authorization': 'Bearer $token'},
    );
    return _communityContactRequestsFromResponse(response, 'requests');
  }

  Future<List<CommunityContactRequest>> getAllCommunityContactRequests({
    required String token,
  }) async {
    final response = await _get(
      '/community/contact-requests',
      headers: {'Authorization': 'Bearer $token'},
    );
    return _communityContactRequestsFromResponse(response, 'requests');
  }

  Future<CommunityContactRequest> acceptCommunityContactRequest({
    required String token,
    required int requestId,
  }) async {
    final response = await _put(
      '/community/contact-requests/$requestId/accept',
      const {},
      headers: {'Authorization': 'Bearer $token'},
    );
    return _communityContactRequestFromResponse(response);
  }

  Future<CommunityContactRequest> rejectCommunityContactRequest({
    required String token,
    required int requestId,
  }) async {
    final response = await _put(
      '/community/contact-requests/$requestId/reject',
      const {},
      headers: {'Authorization': 'Bearer $token'},
    );
    return _communityContactRequestFromResponse(response);
  }

  Future<void> cancelCommunityContactRequest({
    required String token,
    required int requestId,
  }) async {
    await _delete(
      '/community/contact-requests/$requestId/cancel',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<List<CommunityContactPerson>> getCommunityContacts({
    required String token,
  }) async {
    final response = await _get(
      '/community/contacts',
      headers: {'Authorization': 'Bearer $token'},
    );
    final contacts = response['contacts'];
    if (contacts is! List) {
      throw const AuthApiException(
          'The Community contacts response was invalid.');
    }
    try {
      return contacts.map((contact) {
        if (contact is! Map) {
          throw const FormatException('The Community contact was invalid.');
        }
        return CommunityContactPerson.fromJson(
          Map<String, dynamic>.from(contact),
        );
      }).toList(growable: false);
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<void> revokeCommunityContact({
    required String token,
    required int userId,
  }) async {
    await _delete(
      '/community/contacts/$userId',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<bool> blockCommunityMember({
    required String token,
    required int userId,
  }) async {
    final response = await _post(
      '/community/blocks/$userId',
      const {},
      headers: {'Authorization': 'Bearer $token'},
    );
    return response['blocked'] == true;
  }

  Future<void> unblockCommunityMember({
    required String token,
    required int userId,
  }) async {
    await _delete(
      '/community/blocks/$userId',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  CommunityContactRequest _communityContactRequestFromResponse(
    Map<String, dynamic> response,
  ) {
    final request = response['request'];
    if (request is! Map) {
      throw const AuthApiException(
        'The Community contact request response was invalid.',
      );
    }
    try {
      return CommunityContactRequest.fromJson(
        Map<String, dynamic>.from(request),
      );
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  List<CommunityContactRequest> _communityContactRequestsFromResponse(
    Map<String, dynamic> response,
    String key,
  ) {
    final requests = response[key];
    if (requests is! List) {
      throw const AuthApiException(
        'The Community contact requests response was invalid.',
      );
    }
    try {
      return requests.map((request) {
        if (request is! Map) {
          throw const FormatException('The contact request was invalid.');
        }
        return CommunityContactRequest.fromJson(
          Map<String, dynamic>.from(request),
        );
      }).toList(growable: false);
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<CommunityPage<CommunityPost>> getCommunityMemberPosts({
    required String token,
    required int profileId,
    int page = 1,
  }) async {
    final response = await _get(
      '/community/profiles/$profileId/posts?page=$page',
      headers: {'Authorization': 'Bearer $token'},
    );
    try {
      return CommunityPage<CommunityPost>.fromJson(
        response,
        'posts',
        CommunityPost.fromJson,
      );
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  CommunityProfile _communityProfileFromResponse(
    Map<String, dynamic> response,
  ) {
    final profile = response['profile'];
    if (profile is! Map) {
      throw const AuthApiException(
          'The Community profile response was invalid.');
    }
    try {
      return CommunityProfile.fromJson(Map<String, dynamic>.from(profile));
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  CommunityPost _communityPostFromResponse(Map<String, dynamic> response) {
    final post = response['post'];
    if (post is! Map) {
      throw const AuthApiException('The Community post response was invalid.');
    }
    try {
      return CommunityPost.fromJson(Map<String, dynamic>.from(post));
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<Map<String, dynamic>> _communityMultipartPost(
    String path, {
    required String token,
    required Map<String, String> fields,
    XFile? image,
    String imageField = 'image',
    List<XFile> images = const [],
    String imagesField = 'images[]',
  }) async {
    final request = http.MultipartRequest('POST', _apiUri(path))
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      })
      ..fields.addAll(fields);
    if (image != null) {
      request.files.add(http.MultipartFile.fromBytes(
        imageField,
        await image.readAsBytes(),
        filename: image.name,
      ));
    }
    for (final image in images) {
      request.files.add(http.MultipartFile.fromBytes(
        imagesField,
        await image.readAsBytes(),
        filename: image.name,
      ));
    }
    try {
      final streamed = await _client.send(request).timeout(_uploadTimeout);
      return _decodeResponse(
        await http.Response.fromStream(streamed).timeout(_uploadTimeout),
      );
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
    final response = await _get('/me', headers: {
      'Authorization': 'Bearer $token',
    });

    if (response['id'] == null) {
      throw const AuthApiException('The saved session is no longer valid.');
    }

    return response;
  }

  Future<Map<String, dynamic>> getAccountAccess({
    required String token,
  }) async {
    final response = await _get('/account/access', headers: {
      'Authorization': 'Bearer $token',
    });
    if (response['has_main_app_access'] is! bool ||
        response['roles'] is! List) {
      throw const AuthApiException('The account access response was invalid.');
    }
    return response;
  }

  Future<Map<String, dynamic>> upgradeAccount({
    required String token,
    required String role,
    required String name,
    required String location,
  }) async {
    final response = await _post(
      '/account/upgrade',
      {
        'role': role,
        'name': name,
        'location': location,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    final user = response['user'];
    if (user is Map<String, dynamic>) return user;
    if (user is Map) return Map<String, dynamic>.from(user);
    throw const AuthApiException('The account upgrade response was invalid.');
  }

  Future<void> logout({required String token}) async {
    await _post(
      '/auth/logout',
      const {},
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> registerPushToken({
    required String token,
    required String firebaseToken,
    required String platform,
  }) async {
    await _post(
      '/push-tokens',
      {
        'token': firebaseToken,
        'platform': platform,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> removePushToken({
    required String token,
    required String firebaseToken,
  }) async {
    await _delete(
      '/push-tokens',
      headers: {'Authorization': 'Bearer $token'},
      body: {'token': firebaseToken},
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
    int beforeId = 0,
  }) async {
    final response = await _get(
      '/projects/$projectId/members/$memberUserId/messages'
      '?after_id=$afterId&before_id=$beforeId',
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
    int beforeId = 0,
  }) async {
    final response = await _get(
      '/projects/$projectId/group-chat?after_id=$afterId&before_id=$beforeId',
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

  Future<List<ProjectChatConversation>> getChats({
    required String token,
  }) async {
    final response = await _get('/chats', headers: {
      'Authorization': 'Bearer $token',
    });
    final chats = response['chats'];
    if (chats is! List) {
      throw const AuthApiException('The chat list response was invalid.');
    }
    try {
      return chats.map((chat) {
        if (chat is Map) {
          return ProjectChatConversation.fromJson(
            Map<String, dynamic>.from(chat),
          );
        }
        throw const FormatException('The chat list response was invalid.');
      }).toList();
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<ProjectMessage> forwardChatMessage({
    required String token,
    required String projectId,
    required String sourceType,
    required int sourceMessageId,
    required String targetType,
    int? sourceMemberUserId,
    int? targetMemberUserId,
  }) async {
    final response = await _post(
      '/projects/$projectId/chat/forward',
      {
        'source_type': sourceType,
        'source_message_id': sourceMessageId,
        if (sourceMemberUserId != null)
          'source_member_user_id': sourceMemberUserId,
        'target_type': targetType,
        if (targetMemberUserId != null)
          'target_member_user_id': targetMemberUserId,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    return _parseChatMessage(response);
  }

  Future<void> markProjectGroupChatRead({
    required String token,
    required String projectId,
  }) async {
    await _post(
      '/projects/$projectId/group-chat/read',
      const {},
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> markDirectChatRead({
    required String token,
    required String projectId,
    required int memberUserId,
  }) async {
    await _post(
      '/projects/$projectId/members/$memberUserId/messages/read',
      const {},
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<Map<String, dynamic>> authenticateChatChannel({
    required String token,
    required String socketId,
    required String channelName,
  }) {
    return _post(
      '/broadcasting/auth',
      {'socket_id': socketId, 'channel_name': channelName},
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<ProjectMessage> sendProjectGroupLocation({
    required String token,
    required String projectId,
    required double latitude,
    required double longitude,
    required String address,
    int? replyToMessageId,
  }) async {
    final response = await _post(
      '/projects/$projectId/group-chat/location',
      {
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    return _parseChatMessage(response);
  }

  Future<ProjectMessage> sendDirectLocation({
    required String token,
    required String projectId,
    required int memberUserId,
    required double latitude,
    required double longitude,
    required String address,
    int? replyToMessageId,
  }) async {
    final response = await _post(
      '/projects/$projectId/members/$memberUserId/messages/location',
      {
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    return _parseChatMessage(response);
  }

  Future<ProjectMessage> updateProjectGroupMessage({
    required String token,
    required String projectId,
    required int messageId,
    required String body,
  }) async {
    final response = await _patch(
      '/projects/$projectId/group-chat/messages/$messageId',
      {'body': body},
      headers: {'Authorization': 'Bearer $token'},
    );
    return _parseChatMessage(response);
  }

  Future<ProjectMessage> deleteProjectGroupMessage({
    required String token,
    required String projectId,
    required int messageId,
  }) async {
    final response = await _delete(
      '/projects/$projectId/group-chat/messages/$messageId',
      headers: {'Authorization': 'Bearer $token'},
    );
    return _parseChatMessage(response);
  }

  Future<ProjectMessage> updateDirectMessage({
    required String token,
    required String projectId,
    required int memberUserId,
    required int messageId,
    required String body,
  }) async {
    final response = await _patch(
      '/projects/$projectId/members/$memberUserId/messages/$messageId',
      {'body': body},
      headers: {'Authorization': 'Bearer $token'},
    );
    return _parseChatMessage(response);
  }

  Future<ProjectMessage> deleteDirectMessage({
    required String token,
    required String projectId,
    required int memberUserId,
    required int messageId,
  }) async {
    final response = await _delete(
      '/projects/$projectId/members/$memberUserId/messages/$messageId',
      headers: {'Authorization': 'Bearer $token'},
    );
    return _parseChatMessage(response);
  }

  ProjectMessage _parseChatMessage(Map<String, dynamic> response) {
    final message = response['message'];
    if (message is! Map) {
      throw const AuthApiException('The chat message response was invalid.');
    }
    try {
      return ProjectMessage.fromJson(Map<String, dynamic>.from(message));
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

  Future<List<(ProjectMessage, ProjectMember)>> getProjectDirectFiles({
    required String token,
    required String projectId,
  }) async {
    final response = await _get(
      '/projects/$projectId/chat/files',
      headers: {'Authorization': 'Bearer $token'},
    );
    final files = response['files'];
    if (files is! List) {
      throw const AuthApiException(
          'The private chat files response was invalid.');
    }
    try {
      return files.map((file) {
        if (file is! Map) {
          throw const FormatException(
              'The private chat file response was invalid.');
        }
        final json = Map<String, dynamic>.from(file);
        final member = json['conversation_member'];
        if (member is! Map) {
          throw const FormatException(
              'The private chat participant was missing.');
        }
        return (
          ProjectMessage.fromJson(json),
          ProjectMember.fromJson(Map<String, dynamic>.from(member)),
        );
      }).toList();
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<ProjectMessage> sendProjectGroupVoice({
    required String token,
    required String projectId,
    required File file,
    int? replyToMessageId,
  }) {
    return sendProjectGroupAttachment(
      token: token,
      projectId: projectId,
      file: XFile(file.path),
      messageType: 'voice',
      replyToMessageId: replyToMessageId,
    );
  }

  Future<ProjectMessage> sendProjectGroupAttachment({
    required String token,
    required String projectId,
    required XFile file,
    required String messageType,
    int? replyToMessageId,
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
    if (replyToMessageId != null) {
      request.fields['reply_to_message_id'] = '$replyToMessageId';
    }

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
    int? replyToMessageId,
  }) async {
    final response = await _post(
      '/projects/$projectId/group-chat/messages',
      {
        'body': body,
        if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
      },
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
    int? replyToMessageId,
  }) async {
    final response = await _post(
      '/projects/$projectId/members/$memberUserId/messages',
      {
        'body': body,
        if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
      },
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
    int? replyToMessageId,
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
    if (replyToMessageId != null) {
      request.fields['reply_to_message_id'] = '$replyToMessageId';
    }

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

  Future<Map<String, dynamic>> _put(
    String path,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) async {
    final uri = _apiUri(path);
    late final http.Response response;

    try {
      response = await _client
          .put(
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
    Map<String, dynamic>? body,
  }) async {
    final uri = _apiUri(path);
    late final http.Response response;

    try {
      response = await _client
          .delete(
            uri,
            headers: {
              'Accept': 'application/json',
              if (body != null) 'Content-Type': 'application/json',
              ...headers,
            },
            body: body == null ? null : jsonEncode(body),
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
        _messageFrom(data, statusCode: response.statusCode),
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

  String _messageFrom(
    Map<String, dynamic> data, {
    required int statusCode,
  }) {
    final errors = data['errors'];
    if (errors is Map<String, dynamic>) {
      for (final value in errors.values) {
        if (value is List && value.isNotEmpty) return value.first.toString();
      }
    }

    final message = data['message'];
    if (message is String && message.isNotEmpty) return message;
    return 'The server returned an unexpected response (HTTP $statusCode). '
        'Please try again.';
  }
}
