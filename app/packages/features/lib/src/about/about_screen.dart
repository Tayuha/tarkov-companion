import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import '../theme/app_primitives.dart';
import '../theme/app_tokens.dart';

/// Stable keys for the About screen.
abstract final class AboutKeys {
  static const Key screen = Key('about-screen');
  static const Key appVersion = Key('about-app-version');
  static const Key bundleVersion = Key('about-bundle-version');
  static const Key datasetAge = Key('about-dataset-age');
  static const Key licence = Key('about-licence');
  static const Key attribution = Key('about-attribution');
}

/// The About screen: build version, data provenance, licence and attribution.
///
/// It is reachable from the shell footer. All values come from the opened
/// session; the screen itself performs no I/O and opens no dialog.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.appVersion, this.data, this.now});

  /// The application build version, for example `0.1.0`.
  final String appVersion;

  /// The locally applied bundle summary, or `null` when the session has not
  /// inspected the data state.
  final DataBundleStatus? data;

  /// Test seam for deterministic dataset ages.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final current = (now ?? DateTime.now)();
    final data = this.data;

    return Scaffold(
      key: AboutKeys.screen,
      appBar: AppBar(title: const Text('About')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(tokens.spaceXl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('TARKOV COMPANION', style: tokens.displayStyle),
                SizedBox(height: tokens.spaceSm),
                Text(
                  'Local-first Escape from Tarkov companion',
                  style: tokens.h2Style.copyWith(color: tokens.muted),
                ),
                SizedBox(height: tokens.spaceXl),
                AppPanel(
                  label: 'Application',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _InfoRow(
                        label: 'Version',
                        value: appVersion,
                        valueKey: AboutKeys.appVersion,
                      ),
                      _InfoRow(label: 'Licence', value: 'MIT'),
                      _InfoRow(
                        label: 'Platform',
                        value: 'Linux, Windows and Android',
                      ),
                    ],
                  ),
                ),
                SizedBox(height: tokens.spaceLg),
                AppPanel(
                  label: 'Data bundle',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _InfoRow(
                        label: 'Bundle / manifest',
                        value: _bundleVersion(data),
                        valueKey: AboutKeys.bundleVersion,
                      ),
                      _InfoRow(
                        label: 'Generated upstream',
                        value: _date(data?.manifestGeneratedAt),
                      ),
                      _InfoRow(
                        label: 'Last checked',
                        value: _date(data?.manifestCheckedAt),
                      ),
                      _InfoRow(
                        label: 'Datasets applied',
                        value: data == null
                            ? 'Not inspected'
                            : '${data.appliedDatasets} of '
                                  '${data.expectedDatasets}',
                      ),
                      _InfoRow(
                        label: 'Dataset age',
                        value: _datasetAge(data, current),
                        valueKey: AboutKeys.datasetAge,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: tokens.spaceLg),
                AppPanel(
                  label: 'Attribution',
                  child: Column(
                    key: AboutKeys.attribution,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Game data is provided by tarkov.dev, the community '
                        'API for Escape from Tarkov data, and is used under '
                        'the terms published by that project.',
                        style: tokens.bodyStyle,
                      ),
                      SizedBox(height: tokens.spaceSm),
                      Text(
                        'Escape from Tarkov is a registered trademark of '
                        'Battlestate Games Limited. Tarkov Companion is an '
                        'unofficial, fan-made companion and is not affiliated '
                        'with or endorsed by Battlestate Games.',
                        style: tokens.bodyStyle,
                      ),
                      SizedBox(height: tokens.spaceSm),
                      Text(
                        'No game art or other game assets are bundled with '
                        'this application. Item images are fetched from the '
                        'tarkov.dev CDN at runtime and remain the property of '
                        'their owners.',
                        style: tokens.bodyStyle,
                      ),
                      SizedBox(height: tokens.spaceSm),
                      Text(
                        'tarkov.dev — https://tarkov.dev',
                        style: tokens.dataStyle.copyWith(color: tokens.info),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: tokens.spaceLg),
                AppPanel(
                  label: 'MIT Licence',
                  child: Column(
                    key: AboutKeys.licence,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Copyright (c) 2026 Tarkov Companion contributors',
                        style: tokens.dataStyle.copyWith(color: tokens.muted),
                      ),
                      SizedBox(height: tokens.spaceSm),
                      Text(
                        'Permission is hereby granted, free of charge, to any '
                        'person obtaining a copy of this software and '
                        'associated documentation files (the "Software"), to '
                        'deal in the Software without restriction, including '
                        'without limitation the rights to use, copy, modify, '
                        'merge, publish, distribute, sublicense, and/or sell '
                        'copies of the Software, and to permit persons to whom '
                        'the Software is furnished to do so, subject to the '
                        'following conditions:',
                        style: tokens.bodyStyle,
                      ),
                      SizedBox(height: tokens.spaceSm),
                      Text(
                        'The above copyright notice and this permission notice '
                        'shall be included in all copies or substantial '
                        'portions of the Software.',
                        style: tokens.bodyStyle,
                      ),
                      SizedBox(height: tokens.spaceSm),
                      Text(
                        'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF '
                        'ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT '
                        'LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS '
                        'FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO '
                        'EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE '
                        'LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, '
                        'WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, '
                        'ARISING FROM, OUT OF OR IN CONNECTION WITH THE '
                        'SOFTWARE OR THE USE OR OTHER DEALINGS IN THE '
                        'SOFTWARE.',
                        style: tokens.bodyStyle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _bundleVersion(DataBundleStatus? data) {
    if (data == null) {
      return 'Not inspected';
    }
    final manifest = data.manifestVersion;
    final bundle = data.bundleSchemaVersion;
    if (manifest == null && bundle == null) {
      return 'No manifest cached';
    }
    return 'manifest ${manifest ?? '—'} · schema ${bundle ?? '—'}';
  }

  String _datasetAge(DataBundleStatus? data, DateTime now) {
    if (data == null) {
      return 'Not inspected';
    }
    final age = data.datasetAgeAt(now);
    if (age == null) {
      return 'No data applied';
    }
    if (age.inMinutes < 1) {
      return 'Applied just now';
    }
    if (age.inHours < 1) {
      return '${age.inMinutes} min old';
    }
    if (age.inDays < 1) {
      return '${age.inHours} h old';
    }
    final days = age.inDays;
    return '$days ${days == 1 ? 'day' : 'days'} old';
  }

  String _date(DateTime? value) {
    if (value == null) {
      return 'Not available';
    }
    final utc = value.toUtc();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
        '${two(utc.hour)}:${two(utc.minute)} UTC';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueKey});

  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 180, child: AppSectionLabel(label)),
          SizedBox(width: tokens.spaceMd),
          Expanded(
            child: Text(
              value,
              key: valueKey,
              style: tokens.dataStyle.copyWith(color: tokens.text),
            ),
          ),
        ],
      ),
    );
  }
}
