import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

void main() {
  testWidgets('renders a title and optional subtitle', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SectionHeader(title: 'Items', subtitle: 'All known items'),
        ),
      ),
    );

    expect(find.text('Items'), findsOneWidget);
    expect(find.text('All known items'), findsOneWidget);
  });

  testWidgets('omits the subtitle when none is given', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SectionHeader(title: 'Quests')),
      ),
    );

    expect(find.text('Quests'), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
  });
}
