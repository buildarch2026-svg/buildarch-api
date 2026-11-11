import 'package:flutter/material.dart';

import '../models/community.dart';
import '../navigation/community_navigation.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../navigation/profile_navigation.dart';
import '../theme/app_colors.dart';
import '../widgets/app_bottom_nav.dart';
import 'all_project_files_screen.dart';
import 'community_feed_screen.dart';
import 'community_registration_screen.dart';
import 'project_chats_screen.dart';
import 'projects_screen.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  bool _loading = true;
  String? _error;
  String? _token;
  CommunityProfile? _profile;
  Map<String, dynamic> _user = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await AuthSessionService.instance.readToken();
      if (token == null || token.isEmpty) {
        throw const AuthApiException(
          'Your session expired. Please sign in again.',
          statusCode: 401,
        );
      }
      final results = await Future.wait<Object?>([
        AuthApiService.instance.getCommunityProfile(token: token),
        AuthSessionService.instance.readUser(),
      ]);
      if (!mounted) return;
      setState(() {
        _token = token;
        _profile = results[0] as CommunityProfile?;
        _user = results[1] as Map<String, dynamic>? ?? const {};
        _loading = false;
      });
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      }
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your Community profile. Please retry.';
          _loading = false;
        });
      }
    }
  }

  void _onTabSelected(AppTab tab) {
    if (tab == AppTab.community) return;
    if (!_hasMainAppAccess && tab != AppTab.profile) return;
    if (tab == AppTab.projects) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const ProjectsScreen()),
      );
      return;
    }
    if (tab == AppTab.chat) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const ProjectChatsScreen()),
      );
      return;
    }
    if (tab == AppTab.files) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AllProjectFilesScreen()),
      );
      return;
    }
    ProfileNavigation.open(
      context,
      onUpgrade: _hasMainAppAccess
          ? null
          : () => CommunityNavigation.startUpgrade(context),
    );
  }

  bool get _hasMainAppAccess {
    final role = _user['role'];
    return role is String &&
        const {
          'homeOwner',
          'homeowner',
          'contractor',
          'designer',
          'architect',
          'engineer',
          'interiorDesigner',
        }.contains(role);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(title: const Text('Build Arch Community')),
        body: const Center(child: CircularProgressIndicator()),
        bottomNavigationBar: AppBottomNav(
          current: AppTab.community,
          onTap: _onTabSelected,
          communityOnly: !_hasMainAppAccess,
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(title: const Text('Build Arch Community')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 44),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: AppBottomNav(
          current: AppTab.community,
          onTap: _onTabSelected,
          communityOnly: !_hasMainAppAccess,
        ),
      );
    }

    final token = _token!;
    final profile = _profile;
    if (profile == null) {
      return CommunityRegistrationScreen(
        token: token,
        user: _user,
        onRegistered: (createdProfile) {
          if (mounted) setState(() => _profile = createdProfile);
        },
        onTabSelected: _onTabSelected,
        communityOnly: !_hasMainAppAccess,
      );
    }
    return CommunityFeedScreen(
      token: token,
      profile: profile,
      hasMainAppAccess: _hasMainAppAccess,
      onTabSelected: _onTabSelected,
      onProfileUpdated: (updatedProfile) {
        if (mounted) setState(() => _profile = updatedProfile);
      },
    );
  }
}
