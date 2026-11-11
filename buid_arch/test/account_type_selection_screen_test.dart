import 'package:buid_arch/screens/account_type_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps content near the top and icons prominent on phones',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: AccountTypeSelectionScreen()),
    );

    expect(tester.getTopLeft(find.text('Choose your experience')).dy,
        lessThan(180));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints?.maxWidth == 56 &&
            widget.constraints?.maxHeight == 56,
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('keeps account choices compact on a wide screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: AccountTypeSelectionScreen()),
    );

    expect(find.text('Choose your experience'), findsOneWidget);
    expect(find.text('Project management'), findsOneWidget);
    expect(find.text('Community'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);

    final content = find.byWidgetPredicate(
      (widget) =>
          widget is ConstrainedBox && widget.constraints.maxWidth == 560,
    );
    expect(tester.getSize(content).width, 560);
  });

  testWidgets('role selection back button returns to account choices',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AccountTypeSelectionScreen()),
    );

    await tester.tap(find.text('Project management'));
    await tester.pumpAndSettle();
    expect(find.text('Choose Your Role'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Choose your experience'), findsOneWidget);
  });
}
