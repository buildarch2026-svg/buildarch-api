import 'package:flutter/material.dart';

enum ProjectType { newConstruction, renovation, interiorDesigning }

extension ProjectTypeInfo on ProjectType {
  String get apiValue => switch (this) {
        ProjectType.newConstruction => 'new_construction',
        ProjectType.renovation => 'renovation',
        ProjectType.interiorDesigning => 'interior_designing',
      };

  String get label => switch (this) {
        ProjectType.newConstruction => 'New Construction',
        ProjectType.renovation => 'Renovation',
        ProjectType.interiorDesigning => 'Interior Designing',
      };

  String get description => switch (this) {
        ProjectType.newConstruction => 'Ground-up residential build',
        ProjectType.renovation => 'Structural remodeling & additions',
        ProjectType.interiorDesigning => 'Finishes, cabinetry & layout',
      };

  IconData get icon => switch (this) {
        ProjectType.newConstruction => Icons.apartment,
        ProjectType.renovation => Icons.build,
        ProjectType.interiorDesigning => Icons.design_services_outlined,
      };
}
