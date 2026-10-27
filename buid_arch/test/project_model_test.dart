import 'package:buid_arch/models/project.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('project reads joined membership role and inviter from API', () {
    final project = Project.fromJson({
      'id': 23,
      'name': 'Shared home',
      'location': 'Kochi, Kerala',
      'type': 'renovation',
      'is_owner': false,
      'member_role': 'contractor',
      'invited_by_name': 'Project Owner',
    });

    expect(project.isOwner, isFalse);
    expect(project.memberRole, 'contractor');
    expect(project.invitedByName, 'Project Owner');
  });
}
