import 'package:buid_arch/models/project_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses chat replies, edit state, and shared coordinates', () {
    final message = ProjectMessage.fromJson({
      'id': 42,
      'body': 'Meet here',
      'message_type': 'location',
      'sender_user_id': 12,
      'sender_name': 'Site Lead',
      'sender_designation': 'Contractor',
      'forwarded_from_name': 'Home Owner',
      'reply_to_message_id': 40,
      'reply_to': {
        'id': 40,
        'body': 'Where should we meet?',
        'message_type': 'text',
        'sender_name': 'Home Owner',
        'deleted_at': null,
      },
      'edited_at': '2026-11-02T10:00:00+00:00',
      'location_latitude': 9.9312,
      'location_longitude': 76.2673,
      'location_address': 'Marine Drive, Kochi',
      'read_by_user_ids': [15, 18],
      'created_at': '2026-11-02T10:01:00+00:00',
    });

    expect(message.senderDesignation, 'Contractor');
    expect(message.forwardedFromName, 'Home Owner');
    expect(message.replyToMessageId, 40);
    expect(message.replyTo?.body, 'Where should we meet?');
    expect(message.editedAt, isNotNull);
    expect(message.locationLatitude, 9.9312);
    expect(message.locationLongitude, 76.2673);
    expect(message.locationAddress, 'Marine Drive, Kochi');
    expect(message.readByUserIds, [15, 18]);
    expect(message.isDeleted, isFalse);
  });
}
