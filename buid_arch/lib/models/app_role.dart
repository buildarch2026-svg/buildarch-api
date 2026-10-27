import 'package:flutter/material.dart';

/// Roles a person can choose when they register.
enum AppRole { homeOwner, contractor, designer }

extension AppRoleInfo on AppRole {
  String get label => switch (this) {
        AppRole.homeOwner => 'Home Owner',
        AppRole.contractor => 'Contractor',
        AppRole.designer => 'Designer',
      };

  String get packageName => switch (this) {
        AppRole.homeOwner => 'Lite',
        AppRole.contractor => 'Premium Plus',
        AppRole.designer => 'Premium',
      };

  String get description => switch (this) {
        AppRole.homeOwner => 'Build, renovate and track your home project',
        AppRole.contractor => 'Manage estimates, invoices and daily progress',
        AppRole.designer => 'Share designs, drawings and approvals',
      };

  IconData get icon => switch (this) {
        AppRole.homeOwner => Icons.home_outlined,
        AppRole.contractor => Icons.engineering_outlined,
        AppRole.designer => Icons.design_services_outlined,
      };
}
