import 'package:buid_arch/models/project_member.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('project member reads project-specific designation', () {
    final member = ProjectMember.fromJson({
      'user_id': 42,
      'name': 'Rajesh',
      'designation': 'Electrical Consultant',
      'role': 'contractor',
    });

    expect(member.name, 'Rajesh');
    expect(member.designation, 'Electrical Consultant');
  });

  test('project member accepts responses without a designation', () {
    final member = ProjectMember.fromJson({
      'user_id': 42,
      'name': 'Arun',
      'role': 'contractor',
    });

    expect(member.name, 'Arun');
    expect(member.designation, isNull);
  });
}
