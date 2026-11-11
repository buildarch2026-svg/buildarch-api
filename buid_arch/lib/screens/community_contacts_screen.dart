import 'dart:async';

import 'package:flutter/material.dart';

import '../models/community.dart';
import '../navigation/community_navigation.dart';
import '../services/auth_api_service.dart';
import '../services/phone_call_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/community_avatar.dart';
import '../widgets/community_contact_action.dart';
import 'community_profile_screen.dart';

class CommunityContactsScreen extends StatefulWidget {
  const CommunityContactsScreen({
    super.key,
    required this.token,
    this.initialTab = 0,
  });

  final String token;
  final int initialTab;

  @override
  State<CommunityContactsScreen> createState() =>
      _CommunityContactsScreenState();
}

class _CommunityContactsScreenState extends State<CommunityContactsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 4,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 3),
  );
  CommunityProfile? _myProfile;
  List<CommunityContactRequest> _requests = const [];
  List<CommunityContactPerson> _contacts = const [];
  bool _loading = true;
  String? _error;
  int? _workingContactId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait<Object?>([
        AuthApiService.instance.getCommunityProfile(token: widget.token),
        AuthApiService.instance.getAllCommunityContactRequests(
          token: widget.token,
        ),
        AuthApiService.instance.getCommunityContacts(token: widget.token),
      ]);
      if (!mounted) return;
      setState(() {
        _myProfile = result[0] as CommunityProfile?;
        _requests = result[1] as List<CommunityContactRequest>;
        _contacts = result[2] as List<CommunityContactPerson>;
        _loading = false;
      });
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      }
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load Community contacts.';
        _loading = false;
      });
    }
  }

  Future<void> _openProfile(CommunityContactPerson person) async {
    final profileId = person.profileId;
    if (profileId == null) return;
    try {
      final profile = await AuthApiService.instance.getCommunityMemberProfile(
        token: widget.token,
        profileId: profileId,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CommunityProfileScreen(
            token: widget.token,
            profile: profile,
            isCurrentUser: false,
          ),
        ),
      );
      await _load();
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      } else if (mounted) {
        _message(error.message);
      }
    } catch (_) {
      if (mounted) _message('Could not open this Community profile.');
    }
  }

  Future<void> _call(CommunityContactPerson person) async {
    if (_workingContactId != null) return;
    setState(() => _workingContactId = person.userId);
    try {
      final status = await AuthApiService.instance.getCommunityContactStatus(
        token: widget.token,
        userId: person.userId,
      );
      if (status.status != 'accepted') {
        await _load();
        if (mounted) {
          _message(
            'Call access is not enabled yet. Send a call request to connect.',
          );
        }
        return;
      }
      await PhoneCallService().call(status.phoneNumber);
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      } else if (mounted) {
        _message(error.message);
      }
    } on PhoneCallException catch (error) {
      final message = switch (error.failure) {
        PhoneCallFailure.phoneUnavailable =>
          'Phone number is not available for this contact.',
        PhoneCallFailure.invalidNumber =>
          'This contact has an invalid phone number.',
        PhoneCallFailure.notSupported =>
          'This device does not support opening a phone dialer.',
        PhoneCallFailure.launchFailed =>
          'Could not open the phone dialer. Please try again.',
      };
      if (mounted) _message(message);
    } catch (_) {
      if (mounted) _message('Could not open the phone dialer.');
    } finally {
      if (mounted) setState(() => _workingContactId = null);
    }
  }

  Future<void> _revoke(CommunityContactPerson person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke phone contact?'),
        content: Text(
          'You and ${person.displayName} will both lose the ability to call each other through Community.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep contact'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke permission'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _workingContactId = person.userId);
    try {
      await AuthApiService.instance.revokeCommunityContact(
        token: widget.token,
        userId: person.userId,
      );
      await _load();
      if (mounted) _message('Phone contact permission revoked.');
    } on AuthApiException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('Could not revoke phone contact permission.');
    } finally {
      if (mounted) setState(() => _workingContactId = null);
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Community contacts'),
        backgroundColor: AppColors.surface,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            const Tab(
              text: 'All Contacts',
              icon: Icon(Icons.people_alt_outlined),
            ),
            Tab(
              text: 'Requests',
              icon: Badge(
                isLabelVisible: _pendingIncomingCount > 0,
                label: Text('$_pendingIncomingCount'),
                child: const Icon(Icons.mark_email_unread_outlined),
              ),
            ),
            const Tab(
              text: 'Pending',
              icon: Icon(Icons.hourglass_top),
            ),
            Tab(
              text: 'Accepted',
              icon: Badge(
                isLabelVisible: _contacts.isNotEmpty,
                label: Text('${_contacts.length}'),
                child: const Icon(Icons.call),
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorState()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _allList(),
                    _requestsList(),
                    _pendingList(),
                    _contactsList(),
                  ],
                ),
    );
  }

  int get _pendingIncomingCount {
    final userId = _myProfile?.userId;
    if (userId == null) return 0;
    return _requests
        .where((request) =>
            request.receiverId == userId && request.status == 'pending')
        .length;
  }

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
      );

  Widget _requestsList() {
    final userId = _myProfile?.userId;
    final relevant = _requests.where((request) =>
        request.receiverId == userId && request.status == 'pending');
    if (relevant.isEmpty) {
      return _empty(
        icon: Icons.mark_email_read_outlined,
        title: 'No incoming requests',
        subtitle: 'New call requests will appear here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: relevant.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final request = relevant.elementAt(index);
          final incoming = request.receiverId == userId;
          final person = incoming ? request.requester : request.receiver;
          return _requestCard(request, person, incoming);
        },
      ),
    );
  }

  Widget _pendingList() {
    final userId = _myProfile?.userId;
    final relevant = _requests.where((request) =>
        request.requesterId == userId && request.status == 'pending');
    if (relevant.isEmpty) {
      return _empty(
        icon: Icons.hourglass_empty,
        title: 'No pending requests',
        subtitle: 'Call requests you have sent will appear here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: relevant.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final request = relevant.elementAt(index);
          return _requestCard(request, request.receiver, false);
        },
      ),
    );
  }

  Widget _allList() {
    final userId = _myProfile?.userId;
    final relevant = _requests.where((request) =>
        request.status == 'pending' || request.status == 'rejected');
    if (_contacts.isEmpty && relevant.isEmpty) {
      return _empty(
        icon: Icons.people_outline,
        title: 'No Community contacts yet',
        subtitle: 'Request call access from a member’s profile to get started.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (relevant.isNotEmpty) ...[
            _sectionTitle('Requests'),
            for (final request in relevant) ...[
              _requestCard(
                request,
                request.receiverId == userId
                    ? request.requester
                    : request.receiver,
                request.receiverId == userId,
              ),
              const SizedBox(height: 10),
            ],
          ],
          if (_contacts.isNotEmpty) ...[
            _sectionTitle('Accepted contacts'),
            for (final person in _contacts) ...[
              _contactCard(person),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(title, style: AppTextStyles.titleMd),
      );

  Widget _requestCard(
    CommunityContactRequest request,
    CommunityContactPerson person,
    bool incoming,
  ) {
    final pending = request.status == 'pending';
    final statusLabel = request.status == 'rejected'
        ? 'Contact Request Declined'
        : incoming
            ? 'Wants to connect with you by phone'
            : 'Request Pending';
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            InkWell(
              onTap: () => _openProfile(person),
              child: Row(
                children: [
                  CommunityAvatar(
                    imageUrl: person.profileImageUrl,
                    displayName: person.displayName,
                    radius: 25,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(person.displayName, style: AppTextStyles.titleMd),
                        Text(
                          person.profession,
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        if (person.location?.isNotEmpty == true)
                          Text(
                            person.location!,
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(statusLabel),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
            if (pending) ...[
              const SizedBox(height: 12),
              CommunityContactAction(
                token: widget.token,
                userId: person.userId,
                initialStatus: CommunityContactStatus(
                  status: incoming ? 'incoming_pending' : 'outgoing_pending',
                  requestId: request.id,
                ),
                onStatusChanged: (_) => _load(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _contactsList() {
    if (_contacts.isEmpty) {
      return _empty(
        icon: Icons.people_outline,
        title: 'No accepted contacts yet',
        subtitle: 'Accept a request to connect by phone.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _contacts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          return _contactCard(_contacts[index]);
        },
      ),
    );
  }

  Widget _contactCard(CommunityContactPerson person) {
    final busy = _workingContactId == person.userId;
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: ListTile(
                onTap: () => _openProfile(person),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: CommunityAvatar(
                  imageUrl: person.profileImageUrl,
                  displayName: person.displayName,
                ),
                title: Text(person.displayName),
                subtitle: Text([
                  person.profession,
                  if (person.location?.isNotEmpty == true) person.location!,
                ].join(' · ')),
              ),
            ),
            if (busy)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              IconButton.filledTonal(
                tooltip: 'Call ${person.displayName}',
                onPressed: () => _call(person),
                icon: const Icon(Icons.call_outlined),
              ),
              PopupMenuButton<String>(
                tooltip: 'Contact options',
                onSelected: (_) => _revoke(person),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'revoke',
                    child: Text('Revoke call permission'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _empty({
    required IconData icon,
    required String title,
    required String subtitle,
  }) =>
      ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 90),
          Icon(icon, size: 52, color: AppColors.outline),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center, style: AppTextStyles.titleMd),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMd.copyWith(color: AppColors.outline),
          ),
        ],
      );
}
