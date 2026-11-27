import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import 'support/load_fonts.dart';

const Key _galleryKey = Key('component-gallery');

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadDesignFonts();
  });

  testWidgets('renders every button variant and reports taps', (tester) async {
    var taps = 0;

    await _pump(
      tester,
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppButton(label: 'Primary', onPressed: () => taps++),
                const SizedBox(width: 8),
                const AppButton(
                  label: 'Secondary',
                  variant: AppButtonVariant.secondary,
                ),
                const SizedBox(width: 8),
                const AppButton(
                  label: 'Ghost',
                  variant: AppButtonVariant.ghost,
                ),
                const SizedBox(width: 8),
                const AppButton(
                  label: 'Danger',
                  variant: AppButtonVariant.danger,
                ),
              ],
            ),
            const AppButton(label: 'Disabled'),
          ],
        ),
      ),
    );

    expect(find.text('PRIMARY'), findsOneWidget);
    expect(find.text('SECONDARY'), findsOneWidget);
    expect(find.text('GHOST'), findsOneWidget);
    expect(find.text('DANGER'), findsOneWidget);

    await tester.tap(find.text('PRIMARY'));
    expect(taps, 1);
  });

  testWidgets('renders chips, status badges and section labels', (
    tester,
  ) async {
    await _pump(
      tester,
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionLabel('Filter'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const AppChip(label: 'Flea eligible', selected: true),
                const AppChip(label: 'Neutral'),
                for (final status in AppStatus.values)
                  AppStatusBadge(status: status),
              ],
            ),
          ],
        ),
      ),
    );

    expect(find.text('FILTER'), findsOneWidget);
    expect(find.text('FLEA ELIGIBLE'), findsOneWidget);
    expect(find.text('NEUTRAL'), findsOneWidget);
    expect(find.text('AVAILABLE'), findsOneWidget);
    expect(find.text('IN PROGRESS'), findsOneWidget);
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(find.text('FAILED'), findsOneWidget);
    expect(find.text('LOCKED'), findsOneWidget);
  });

  testWidgets('renders panels, stat tiles, progress and data rows', (
    tester,
  ) async {
    await _pump(
      tester,
      SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppStatTile(
              label: 'Recoil',
              value: '63 / 171',
              subtitle: 'Vertical / horizontal',
            ),
            const SizedBox(height: 12),
            AppPanel(
              label: 'Objective progress',
              child: Column(
                children: [
                  AppProgressBar(
                    value: 0.66,
                    label: 'Find the convoy',
                    trailing: '2 / 3',
                  ),
                  const SizedBox(height: 12),
                  const AppDataRow(
                    name: 'Colt M4A1 5.56x45',
                    meta: 'Assault rifle',
                    value: '114,728 ₽',
                    delta: '+22.0%',
                    selected: true,
                  ),
                  const AppDataRow(
                    name: 'Kappa container',
                    meta: 'Container',
                    value: '—',
                    delta: 'Quest reward',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.text('RECOIL'), findsOneWidget);
    expect(find.text('63 / 171'), findsOneWidget);
    expect(find.text('OBJECTIVE PROGRESS'), findsOneWidget);
    expect(find.text('FIND THE CONVOY'), findsOneWidget);
    expect(find.text('Colt M4A1 5.56x45'), findsOneWidget);
    expect(find.text('114,728 ₽'), findsOneWidget);
    expect(find.text('Kappa container'), findsOneWidget);
  });

  testWidgets('component gallery golden', (tester) async {
    await _pump(tester, const _Gallery());

    expect(find.text('Phosphor green.'), findsOneWidget);
    expect(find.text('MARK IN PROGRESS'), findsOneWidget);
    expect(find.text('COMPLETED'), findsWidgets);

    await expectLater(
      find.byKey(_galleryKey),
      matchesGoldenFile('goldens/gallery.png'),
    );
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(880, 660);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return RepaintBoundary(
      key: _galleryKey,
      child: ColoredBox(
        color: tokens.background,
        child: Padding(
          padding: EdgeInsets.all(tokens.spaceXl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSectionLabel('Tarkov Companion · Visual system'),
              SizedBox(height: tokens.spaceXs),
              Text('Phosphor green.', style: tokens.displayStyle),
              SizedBox(height: tokens.spaceXs),
              Text(
                'Dense data. Quiet chrome. Local first.',
                style: tokens.bodyStyle.copyWith(color: tokens.muted),
              ),
              SizedBox(height: tokens.spaceXl),
              AppSectionLabel('Buttons'),
              SizedBox(height: tokens.spaceSm),
              Wrap(
                spacing: tokens.spaceSm,
                runSpacing: tokens.spaceSm,
                children: [
                  AppButton(label: 'Mark in progress', onPressed: _noop),
                  AppButton(
                    label: 'Mark completed',
                    variant: AppButtonVariant.secondary,
                    onPressed: _noop,
                  ),
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.ghost,
                    onPressed: _noop,
                  ),
                  AppButton(
                    label: 'Delete',
                    variant: AppButtonVariant.danger,
                    onPressed: _noop,
                  ),
                  const AppButton(label: 'Disabled'),
                ],
              ),
              SizedBox(height: tokens.spaceLg),
              AppSectionLabel('Chips and states'),
              SizedBox(height: tokens.spaceSm),
              Wrap(
                spacing: tokens.spaceSm,
                runSpacing: tokens.spaceSm,
                children: [
                  const AppChip(label: 'Flea eligible', selected: true),
                  const AppChip(label: 'Neutral'),
                  for (final status in AppStatus.values)
                    AppStatusBadge(status: status),
                ],
              ),
              SizedBox(height: tokens.spaceLg),
              AppSectionLabel('Inspector statistics'),
              SizedBox(height: tokens.spaceSm),
              Row(
                children: [
                  Expanded(
                    child: AppStatTile(
                      label: 'Tasks completed',
                      value: '184 / 503',
                      subtitle: '36.6% of the PvP catalog',
                      valueColor: tokens.accent,
                    ),
                  ),
                  SizedBox(width: tokens.spaceSm),
                  const Expanded(
                    child: AppStatTile(
                      label: 'Flea low',
                      value: '114,728',
                      unit: '₽',
                    ),
                  ),
                  SizedBox(width: tokens.spaceSm),
                  Expanded(
                    child: AppStatTile(
                      label: '24 h change',
                      value: '+22.0%',
                      subtitle: '7-day trend',
                      valueColor: tokens.success,
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.spaceLg),
              AppProgressBar(
                value: 0.66,
                label: 'Objective progress',
                trailing: '2 / 3 · Find the convoy',
              ),
              SizedBox(height: tokens.spaceLg),
              AppPanel(
                label: 'Flea price · 24 h',
                trailing: Text(
                  'OFFLINE COPY',
                  style: tokens.labelStyle.copyWith(color: tokens.dim),
                ),
                child: Column(
                  children: [
                    AppDataRow(
                      name: 'Colt M4A1 5.56x45',
                      meta: 'Assault rifle · 5.56x45',
                      value: '114,728 ₽',
                      delta: '+22.0%',
                      deltaColor: tokens.success,
                      selected: true,
                    ),
                    AppDataRow(
                      name: 'LEDX Skin Transilluminator',
                      meta: 'Medical · valuable',
                      value: '1,240,000 ₽',
                      delta: '-7.4%',
                      deltaColor: tokens.danger,
                    ),
                    const AppDataRow(
                      name: 'Kappa container',
                      meta: 'Container',
                      value: '—',
                      delta: 'Quest reward',
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AppSectionLabel('Mono labels · signed numbers'),
                  AppSectionLabel('1x · 880 × 660'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _noop() {}
