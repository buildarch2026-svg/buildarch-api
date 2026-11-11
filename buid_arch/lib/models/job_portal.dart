import 'community.dart';

class JobPortalCategory {
  const JobPortalCategory({
    required this.id,
    required this.slug,
    required this.name,
  });

  final int id;
  final String slug;
  final String name;

  factory JobPortalCategory.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final slug = json['slug'];
    final name = json['name'];
    if (id is! num || slug is! String || name is! String) {
      throw const FormatException('The job category response was invalid.');
    }
    return JobPortalCategory(id: id.toInt(), slug: slug, name: name);
  }
}

class JobPortalCompany {
  const JobPortalCompany({
    required this.id,
    required this.name,
    this.userId,
    this.communityProfileId,
    this.logoUrl,
    this.location,
    this.description,
    this.website,
    this.employerType,
  });

  final int id;
  final String name;
  final int? userId;
  final int? communityProfileId;
  final String? logoUrl;
  final String? location;
  final String? description;
  final String? website;
  final String? employerType;

  factory JobPortalCompany.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! num || name is! String) {
      throw const FormatException('The employer response was invalid.');
    }
    return JobPortalCompany(
      id: id.toInt(),
      name: name,
      userId: (json['user_id'] as num?)?.toInt(),
      communityProfileId: (json['community_profile_id'] as num?)?.toInt(),
      logoUrl: json['logo_url'] as String?,
      location: json['location'] as String?,
      description: json['description'] as String?,
      website: json['website'] as String?,
      employerType: json['employer_type'] as String?,
    );
  }
}

class ConstructionJob {
  const ConstructionJob({
    required this.id,
    required this.title,
    required this.employmentType,
    required this.locationName,
    required this.status,
    required this.skills,
    this.description,
    this.experienceRequired,
    this.minSalary,
    this.maxSalary,
    this.salaryType,
    this.qualifications = const [],
    this.latitude,
    this.longitude,
    this.vacancies,
    this.distanceKm,
    this.applicationDeadline,
    this.createdAt,
    this.category,
    this.company,
    this.isSaved = false,
    this.applicationStatus,
    this.contactEmail,
    this.contactPhone,
    this.applicationsCount,
    this.otherCategoryDescription,
    this.contactPreference = 'both',
    this.additionalInstructions,
    this.workStartDate,
  });

  final int id;
  final String title;
  final String? description;
  final String employmentType;
  final String? experienceRequired;
  final double? minSalary;
  final double? maxSalary;
  final String? salaryType;
  final List<String> qualifications;
  final List<String> skills;
  final int? vacancies;
  final String locationName;
  final double? latitude;
  final double? longitude;
  final double? distanceKm;
  final DateTime? applicationDeadline;
  final String status;
  final DateTime? createdAt;
  final JobPortalCategory? category;
  final JobPortalCompany? company;
  final bool isSaved;
  final String? applicationStatus;
  final String? contactEmail;
  final String? contactPhone;
  final int? applicationsCount;
  final String? otherCategoryDescription;
  final String contactPreference;
  final String? additionalInstructions;
  final DateTime? workStartDate;

  factory ConstructionJob.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final employmentType = json['employment_type'];
    final location = json['location_name'];
    final status = json['status'];
    if (id is! num ||
        title is! String ||
        employmentType is! String ||
        location is! String ||
        status is! String) {
      throw const FormatException('The job response was invalid.');
    }
    final categoryJson = json['category'];
    final companyJson = json['company'];
    return ConstructionJob(
      id: id.toInt(),
      title: title,
      description: json['description'] as String?,
      employmentType: employmentType,
      experienceRequired: json['experience_required'] as String?,
      minSalary: _number(json['min_salary']),
      maxSalary: _number(json['max_salary']),
      salaryType: json['salary_type'] as String?,
      qualifications: _strings(json['qualifications']),
      skills: _strings(json['skills']),
      vacancies:
          json['vacancies'] is num ? (json['vacancies'] as num).toInt() : null,
      locationName: location,
      latitude: _number(json['latitude']),
      longitude: _number(json['longitude']),
      distanceKm: _number(json['distance_km']),
      applicationDeadline: _date(json['application_deadline']),
      status: status,
      createdAt: _date(json['created_at']),
      category: categoryJson is Map
          ? JobPortalCategory.fromJson(Map<String, dynamic>.from(categoryJson))
          : null,
      company: companyJson is Map
          ? JobPortalCompany.fromJson(Map<String, dynamic>.from(companyJson))
          : null,
      isSaved: json['is_saved'] == true,
      applicationStatus: json['application_status'] as String?,
      contactEmail: (json['contact'] as Map?)?['email'] as String?,
      contactPhone: (json['contact'] as Map?)?['phone_number'] as String?,
      applicationsCount: json['applications_count'] is num
          ? (json['applications_count'] as num).toInt()
          : null,
      otherCategoryDescription: json['other_category_description'] as String?,
      contactPreference: json['contact_preference'] as String? ?? 'both',
      additionalInstructions: json['additional_instructions'] as String?,
      workStartDate: _date(json['work_start_date']),
    );
  }

  static double? _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static List<String> _strings(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];
}

class JobPortalEmployerProfile {
  const JobPortalEmployerProfile({
    required this.id,
    required this.companyName,
    required this.employerName,
    required this.email,
    required this.phoneNumber,
    required this.companyDescription,
    required this.locationName,
    required this.employerType,
    this.website,
    this.companyLogoUrl,
    this.latitude,
    this.longitude,
  });

  final int id;
  final String companyName;
  final String employerName;
  final String email;
  final String phoneNumber;
  final String companyDescription;
  final String locationName;
  final String employerType;
  final String? website;
  final String? companyLogoUrl;
  final double? latitude;
  final double? longitude;

  factory JobPortalEmployerProfile.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! num) {
      throw const FormatException('The employer profile response was invalid.');
    }
    return JobPortalEmployerProfile(
      id: id.toInt(),
      companyName: _requiredString(json, 'company_name'),
      employerName: _requiredString(json, 'employer_name'),
      email: _requiredString(json, 'email'),
      phoneNumber: _requiredString(json, 'phone_number'),
      companyDescription: _requiredString(json, 'company_description'),
      locationName: _requiredString(json, 'location_name'),
      employerType: _requiredString(json, 'employer_type'),
      website: json['website'] as String?,
      companyLogoUrl: json['company_logo_url'] as String?,
      latitude: _number(json['latitude']),
      longitude: _number(json['longitude']),
    );
  }
}

class JobPortalSeekerProfile {
  const JobPortalSeekerProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.skills,
    required this.hasResume,
    this.currentLocation,
    this.currentLatitude,
    this.currentLongitude,
    this.preferredLocation,
    this.preferredLatitude,
    this.preferredLongitude,
    this.profession,
    this.experienceYears,
    this.education,
    this.bio,
    this.profileImageUrl,
    this.resumeName,
    this.preferredCategories = const [],
    this.preferredEmploymentTypes = const [],
    this.preferredRadiusKm = 25,
    this.expectedSalary,
    this.availableFrom,
    this.notificationsEnabled = false,
  });

  final int id;
  final String fullName;
  final String email;
  final String phoneNumber;
  final List<String> skills;
  final bool hasResume;
  final String? currentLocation;
  final double? currentLatitude;
  final double? currentLongitude;
  final String? preferredLocation;
  final double? preferredLatitude;
  final double? preferredLongitude;
  final String? profession;
  final int? experienceYears;
  final String? education;
  final String? bio;
  final String? profileImageUrl;
  final String? resumeName;
  final List<int> preferredCategories;
  final List<String> preferredEmploymentTypes;
  final int preferredRadiusKm;
  final double? expectedSalary;
  final DateTime? availableFrom;
  final bool notificationsEnabled;

  factory JobPortalSeekerProfile.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! num) {
      throw const FormatException(
          'The job seeker profile response was invalid.');
    }
    return JobPortalSeekerProfile(
      id: id.toInt(),
      fullName: _requiredString(json, 'full_name'),
      email: _requiredString(json, 'email'),
      phoneNumber: _requiredString(json, 'phone_number'),
      skills: _stringList(json['skills']),
      hasResume: json['has_resume'] == true,
      currentLocation: json['current_location'] as String?,
      currentLatitude: _number(json['current_latitude']),
      currentLongitude: _number(json['current_longitude']),
      preferredLocation: json['preferred_location'] as String?,
      preferredLatitude: _number(json['preferred_latitude']),
      preferredLongitude: _number(json['preferred_longitude']),
      profession: json['profession'] as String?,
      experienceYears: json['experience_years'] is num
          ? (json['experience_years'] as num).toInt()
          : null,
      education: json['education'] as String?,
      bio: json['bio'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      resumeName: json['resume_name'] as String?,
      preferredCategories: json['preferred_categories'] is List
          ? (json['preferred_categories'] as List)
              .whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: false)
          : const [],
      preferredEmploymentTypes: _stringList(json['preferred_employment_types']),
      preferredRadiusKm: json['preferred_radius_km'] is num
          ? (json['preferred_radius_km'] as num).toInt()
          : 25,
      expectedSalary: _number(json['expected_salary']),
      availableFrom: json['available_from'] is String
          ? DateTime.tryParse(json['available_from'] as String)
          : null,
      notificationsEnabled: json['notifications_enabled'] == true,
    );
  }
}

class JobPortalApplication {
  const JobPortalApplication({
    required this.id,
    required this.status,
    required this.resumeName,
    required this.appliedAt,
    this.coverLetter,
    this.interviewAt,
    this.employerNote,
    this.resumeUrl,
    this.job,
    this.candidate,
  });

  final int id;
  final String status;
  final String resumeName;
  final DateTime? appliedAt;
  final String? coverLetter;
  final DateTime? interviewAt;
  final String? employerNote;
  final String? resumeUrl;
  final ConstructionJob? job;
  final Map<String, dynamic>? candidate;

  factory JobPortalApplication.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final status = json['status'];
    if (id is! num || status is! String) {
      throw const FormatException('The application response was invalid.');
    }
    final jobJson = json['job'];
    final candidateJson = json['candidate'];
    return JobPortalApplication(
      id: id.toInt(),
      status: status,
      resumeName: json['resume_name'] as String? ?? '',
      appliedAt: json['applied_at'] is String
          ? DateTime.tryParse(json['applied_at'] as String)
          : null,
      coverLetter: json['cover_letter'] as String?,
      interviewAt: json['interview_at'] is String
          ? DateTime.tryParse(json['interview_at'] as String)
          : null,
      employerNote: json['employer_note'] as String?,
      resumeUrl: json['resume_url'] as String?,
      job: jobJson is Map
          ? ConstructionJob.fromJson(Map<String, dynamic>.from(jobJson))
          : null,
      candidate: candidateJson is Map
          ? Map<String, dynamic>.from(candidateJson)
          : null,
    );
  }
}

class JobPortalPage<T> {
  const JobPortalPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
  });

  final List<T> items;
  final int currentPage;
  final int lastPage;

  bool get hasMore => currentPage < lastPage;

  factory JobPortalPage.fromJson(
    Map<String, dynamic> json,
    String key,
    T Function(Map<String, dynamic>) decode,
  ) {
    final raw = json[key];
    if (raw is! Map || raw['data'] is! List) {
      throw FormatException('The $key page response was invalid.');
    }
    final data = (raw['data'] as List).map((value) {
      if (value is! Map) {
        throw FormatException('The $key page item was invalid.');
      }
      return decode(Map<String, dynamic>.from(value));
    }).toList(growable: false);
    final current = raw['current_page'];
    final last = raw['last_page'];
    return JobPortalPage<T>(
      items: data,
      currentPage: current is num ? current.toInt() : 1,
      lastPage: last is num ? last.toInt() : 1,
    );
  }
}

class JobPortalDashboard {
  const JobPortalDashboard({
    required this.jobs,
    required this.myJobsCount,
    required this.myApplicationsCount,
    required this.savedJobsCount,
    this.communityProfile,
  });

  final List<ConstructionJob> jobs;
  final int myJobsCount;
  final int myApplicationsCount;
  final int savedJobsCount;
  final CommunityProfile? communityProfile;

  factory JobPortalDashboard.fromJson(Map<String, dynamic> json) {
    final jobs = json['jobs'];
    if (jobs is! List) {
      throw const FormatException('The job dashboard response was invalid.');
    }
    return JobPortalDashboard(
      jobs: jobs.map((value) {
        if (value is! Map) {
          throw const FormatException('The dashboard job was invalid.');
        }
        return ConstructionJob.fromJson(Map<String, dynamic>.from(value));
      }).toList(growable: false),
      myJobsCount: _int(json['my_jobs_count']),
      myApplicationsCount: _int(json['my_applications_count']),
      savedJobsCount: _int(json['saved_jobs_count']),
      communityProfile: json['community_profile'] is Map
          ? CommunityProfile.fromJson(
              Map<String, dynamic>.from(json['community_profile'] as Map),
            )
          : null,
    );
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('The $key field was invalid.');
  }
  return value;
}

double? _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value');

List<String> _stringList(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];

int _int(Object? value) => value is num ? value.toInt() : 0;
