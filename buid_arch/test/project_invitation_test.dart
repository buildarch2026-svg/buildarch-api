import 'package:buid_arch/models/project_invitation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invitation QR link contains only the opaque token', () {
    final token = List.filled(64, 'a').join();
    final invitation = ProjectInvitation(
      id: 5,
      role: 'contractor',
      status: 'pending',
      token: token,
      createdAt: DateTime.utc(2026, 10, 24),
      expiresAt: DateTime.utc(2026, 10, 31),
    );

    expect(invitation.qrLink.toString(), 'buildarch://invite/$token');
    expect(invitation.qrLink.queryParameters, isEmpty);
  });

  test('invitation details retain project coordinates for member dashboard',
      () {
    final details = ProjectInvitationDetails.fromJson({
      'invitation': {
        'id': 5,
        'role': 'designer',
        'status': 'pending',
        'created_at': '2026-10-24T00:00:00Z',
        'expires_at': '2026-10-31T00:00:00Z',
        'can_accept': true,
        'inviter_name': 'Owner',
        'project': {
          'id': 12,
          'name': 'House',
          'location': 'Kochi, Kerala',
          'type': 'new_construction',
          'progress': 0,
          'latitude': 9.9312,
          'longitude': 76.2673,
          'photo_url': null,
          'owner_name': 'Owner',
        },
      },
    });

    expect(details.canAccept, isTrue);
    expect(details.invitation.role, 'designer');
    expect(details.project.id, '12');
    expect(details.project.latitude, 9.9312);
    expect(details.project.isOwner, isFalse);
  });
}
