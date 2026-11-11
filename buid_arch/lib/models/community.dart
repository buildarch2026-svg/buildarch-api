class CommunityCategory {
  const CommunityCategory({
    required this.id,
    required this.slug,
    required this.name,
  });

  final int id;
  final String slug;
  final String name;

  factory CommunityCategory.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final slug = json['slug'];
    final name = json['name'];
    if (id is! num || slug is! String || name is! String) {
      throw const FormatException('The Community category was invalid.');
    }
    return CommunityCategory(id: id.toInt(), slug: slug, name: name);
  }
}

class CommunityProfile {
  const CommunityProfile({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.profession,
    required this.professionType,
    required this.postsCount,
    this.otherProfession,
    this.bio,
    this.location,
    this.profileImageUrl,
    this.isPhoneVisible = false,
    this.phoneNumber,
    this.email,
    this.latitude,
    this.longitude,
    this.trade,
    this.skills = const [],
    this.experienceYears,
    this.preferredLocation,
    this.preferredLatitude,
    this.preferredLongitude,
    this.preferredCategories = const [],
    this.preferredRadiusKm = 25,
    this.jobNotificationsEnabled = false,
  });

  final int id;
  final int userId;
  final String displayName;
  final String profession;
  final String? professionType;
  final int postsCount;
  final String? otherProfession;
  final String? bio;
  final String? location;
  final String? profileImageUrl;
  final bool isPhoneVisible;
  final String? phoneNumber;
  final String? email;
  final double? latitude;
  final double? longitude;
  final String? trade;
  final List<String> skills;
  final int? experienceYears;
  final String? preferredLocation;
  final double? preferredLatitude;
  final double? preferredLongitude;
  final List<int> preferredCategories;
  final int preferredRadiusKm;
  final bool jobNotificationsEnabled;

  factory CommunityProfile.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final displayName = json['display_name'];
    final profession = json['profession'];
    final professionType = json['profession_type'];
    final count = json['posts_count'];
    if (id is! num ||
        displayName is! String ||
        profession is! String ||
        count is! num) {
      throw const FormatException('The Community profile was invalid.');
    }
    return CommunityProfile(
      id: id.toInt(),
      userId: (json['user_id'] as num?)?.toInt() ?? id.toInt(),
      displayName: displayName,
      profession: profession,
      professionType: professionType is String ? professionType : null,
      postsCount: count.toInt(),
      otherProfession: json['other_profession'] as String?,
      bio: json['bio'] as String?,
      location: json['location'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      isPhoneVisible: json['is_phone_visible'] == true,
      phoneNumber: json['phone_number'] as String?,
      email: json['email'] as String?,
      latitude: _communityNumber(json['latitude']),
      longitude: _communityNumber(json['longitude']),
      trade: json['trade'] as String?,
      skills: json['skills'] is List
          ? (json['skills'] as List).whereType<String>().toList(growable: false)
          : const [],
      experienceYears: json['experience_years'] is num
          ? (json['experience_years'] as num).toInt()
          : null,
      preferredLocation: json['preferred_location'] as String?,
      preferredLatitude: _communityNumber(json['preferred_latitude']),
      preferredLongitude: _communityNumber(json['preferred_longitude']),
      preferredCategories: json['preferred_categories'] is List
          ? (json['preferred_categories'] as List)
              .whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: false)
          : const [],
      preferredRadiusKm: json['preferred_radius_km'] is num
          ? (json['preferred_radius_km'] as num).toInt()
          : 25,
      jobNotificationsEnabled: json['job_notifications_enabled'] == true,
    );
  }

  static double? _communityNumber(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  CommunityProfile copyWith({
    String? displayName,
    String? profession,
    String? professionType,
    int? postsCount,
    String? bio,
    String? location,
    String? profileImageUrl,
    bool? isPhoneVisible,
    String? phoneNumber,
    String? email,
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
    bool removeProfileImage = false,
  }) {
    return CommunityProfile(
      id: id,
      userId: userId,
      displayName: displayName ?? this.displayName,
      profession: profession ?? this.profession,
      professionType: professionType ?? this.professionType,
      postsCount: postsCount ?? this.postsCount,
      otherProfession: professionType == null
          ? otherProfession
          : professionType == 'Other'
              ? otherProfession
              : null,
      bio: bio ?? this.bio,
      location: location ?? this.location,
      profileImageUrl:
          removeProfileImage ? null : profileImageUrl ?? this.profileImageUrl,
      isPhoneVisible: isPhoneVisible ?? this.isPhoneVisible,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      trade: trade ?? this.trade,
      skills: skills ?? this.skills,
      experienceYears: experienceYears ?? this.experienceYears,
      preferredLocation: preferredLocation ?? this.preferredLocation,
      preferredLatitude: preferredLatitude ?? this.preferredLatitude,
      preferredLongitude: preferredLongitude ?? this.preferredLongitude,
      preferredCategories: preferredCategories ?? this.preferredCategories,
      preferredRadiusKm: preferredRadiusKm ?? this.preferredRadiusKm,
      jobNotificationsEnabled:
          jobNotificationsEnabled ?? this.jobNotificationsEnabled,
    );
  }
}

class CommunityContactStatus {
  const CommunityContactStatus({
    required this.status,
    this.requestId,
    this.blockedByMe = false,
    this.phoneNumber,
  });

  final String status;
  final int? requestId;
  final bool blockedByMe;
  final String? phoneNumber;

  factory CommunityContactStatus.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    if (status is! String) {
      throw const FormatException('The Community contact status was invalid.');
    }
    return CommunityContactStatus(
      status: status,
      requestId: (json['request_id'] as num?)?.toInt(),
      blockedByMe: json['blocked_by_me'] == true,
      phoneNumber: json['phone_number'] as String?,
    );
  }
}

class CommunityContactPerson {
  const CommunityContactPerson({
    required this.userId,
    required this.displayName,
    required this.profession,
    this.profileId,
    this.location,
    this.profileImageUrl,
    this.phoneNumber,
  });

  final int userId;
  final int? profileId;
  final String displayName;
  final String profession;
  final String? location;
  final String? profileImageUrl;
  final String? phoneNumber;

  factory CommunityContactPerson.fromJson(Map<String, dynamic> json) {
    final userId = json['user_id'];
    final name = json['display_name'];
    final profession = json['profession'];
    if (userId is! num || name is! String || profession is! String) {
      throw const FormatException('The Community contact member was invalid.');
    }
    return CommunityContactPerson(
      userId: userId.toInt(),
      profileId: (json['profile_id'] as num?)?.toInt(),
      displayName: name,
      profession: profession,
      location: json['location'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      phoneNumber: json['phone_number'] as String?,
    );
  }
}

class CommunityContactRequest {
  const CommunityContactRequest({
    required this.id,
    required this.requesterId,
    required this.receiverId,
    required this.status,
    required this.requester,
    required this.receiver,
  });

  final int id;
  final int requesterId;
  final int receiverId;
  final String status;
  final CommunityContactPerson requester;
  final CommunityContactPerson receiver;

  factory CommunityContactRequest.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final requesterId = json['requester_id'];
    final receiverId = json['receiver_id'];
    final status = json['status'];
    final requester = json['requester'];
    final receiver = json['receiver'];
    if (id is! num ||
        requesterId is! num ||
        receiverId is! num ||
        status is! String ||
        requester is! Map ||
        receiver is! Map) {
      throw const FormatException('The Community contact request was invalid.');
    }
    return CommunityContactRequest(
      id: id.toInt(),
      requesterId: requesterId.toInt(),
      receiverId: receiverId.toInt(),
      status: status,
      requester:
          CommunityContactPerson.fromJson(Map<String, dynamic>.from(requester)),
      receiver:
          CommunityContactPerson.fromJson(Map<String, dynamic>.from(receiver)),
    );
  }
}

class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.content,
    required this.likesCount,
    required this.commentsCount,
    required this.likedByMe,
    required this.createdAt,
    required this.author,
    this.imageUrl,
    this.imageUrls = const [],
    this.category,
  });

  final int id;
  final String content;
  final int likesCount;
  final int commentsCount;
  final bool likedByMe;
  final DateTime? createdAt;
  final CommunityProfile author;
  final String? imageUrl;
  final List<String> imageUrls;
  final CommunityCategory? category;

  factory CommunityPost.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final content = json['content'];
    final author = json['author'];
    final likes = json['likes_count'];
    final comments = json['comments_count'];
    final rawImageUrls = json['image_urls'];
    final imageUrls = rawImageUrls is List
        ? rawImageUrls.whereType<String>().toList(growable: false)
        : const <String>[];
    if (id is! num ||
        content is! String ||
        author is! Map ||
        likes is! num ||
        comments is! num) {
      throw const FormatException('The Community post was invalid.');
    }
    return CommunityPost(
      id: id.toInt(),
      content: content,
      author: CommunityProfile.fromJson(Map<String, dynamic>.from(author)),
      likesCount: likes.toInt(),
      commentsCount: comments.toInt(),
      likedByMe: json['liked_by_me'] == true,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      imageUrl: json['image_url'] as String? ??
          (imageUrls.isEmpty ? null : imageUrls.first),
      imageUrls: imageUrls,
      category: json['category'] is Map
          ? CommunityCategory.fromJson(
              Map<String, dynamic>.from(json['category'] as Map),
            )
          : null,
    );
  }

  CommunityPost copyWith({
    int? likesCount,
    int? commentsCount,
    bool? likedByMe,
  }) {
    return CommunityPost(
      id: id,
      content: content,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      likedByMe: likedByMe ?? this.likedByMe,
      createdAt: createdAt,
      author: author,
      imageUrl: imageUrl,
      imageUrls: imageUrls,
      category: category,
    );
  }
}

class CommunityComment {
  const CommunityComment({
    required this.id,
    required this.postId,
    required this.content,
    required this.author,
    required this.repliesCount,
    required this.createdAt,
    required this.replies,
    this.parentCommentId,
  });

  final int id;
  final int postId;
  final int? parentCommentId;
  final String content;
  final CommunityProfile author;
  final int repliesCount;
  final DateTime? createdAt;
  final List<CommunityComment> replies;

  factory CommunityComment.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final postId = json['post_id'];
    final content = json['content'];
    final author = json['author'];
    final repliesCount = json['replies_count'];
    if (id is! num ||
        postId is! num ||
        content is! String ||
        author is! Map ||
        repliesCount is! num) {
      throw const FormatException('The Community comment was invalid.');
    }
    final repliesJson = json['replies'];
    return CommunityComment(
      id: id.toInt(),
      postId: postId.toInt(),
      parentCommentId: (json['parent_comment_id'] as num?)?.toInt(),
      content: content,
      author: CommunityProfile.fromJson(Map<String, dynamic>.from(author)),
      repliesCount: repliesCount.toInt(),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      replies: repliesJson is List
          ? repliesJson
              .whereType<Map>()
              .map((reply) =>
                  CommunityComment.fromJson(Map<String, dynamic>.from(reply)))
              .toList()
          : const [],
    );
  }
}

class CommunityPage<T> {
  const CommunityPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
  });

  final List<T> items;
  final int currentPage;
  final int lastPage;

  bool get hasMore => currentPage < lastPage;

  factory CommunityPage.fromJson(
    Map<String, dynamic> json,
    String key,
    T Function(Map<String, dynamic>) parse,
  ) {
    final page = json[key];
    if (page is! Map || page['data'] is! List) {
      throw const FormatException('The Community page response was invalid.');
    }
    final data = Map<String, dynamic>.from(page);
    final current = data['current_page'];
    final last = data['last_page'];
    if (current is! num || last is! num) {
      throw const FormatException('The Community pagination was invalid.');
    }
    try {
      return CommunityPage<T>(
        items: (data['data'] as List).map((item) {
          if (item is Map) return parse(Map<String, dynamic>.from(item));
          throw const FormatException('The Community item was invalid.');
        }).toList(),
        currentPage: current.toInt(),
        lastPage: last.toInt(),
      );
    } on FormatException {
      rethrow;
    }
  }
}
