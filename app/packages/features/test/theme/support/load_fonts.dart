import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the bundled design-system fonts into the test engine.
///
/// Widget tests do not load fonts declared in `app/pubspec.yaml` automatically,
/// and this package does not own those assets. Reading the files directly keeps
/// the golden deterministic and makes the gallery show real type instead of
/// Ahem boxes. The path probes cover `flutter test` from `app/` and from
/// `app/packages/features/`.
Future<void> loadDesignFonts() async {
  final directory = _fontDirectory();
  if (directory == null) {
    throw StateError(
      'Could not find app/assets/fonts. Run the test from app/ or from the '
      'features package directory.',
    );
  }

  final ui = FontLoader('Fira Sans Condensed')
    ..addFont(_read(directory, 'FiraSansCondensed-Regular.ttf'))
    ..addFont(_read(directory, 'FiraSansCondensed-SemiBold.ttf'))
    ..addFont(_read(directory, 'FiraSansCondensed-Bold.ttf'));
  final mono = FontLoader('DejaVu Sans Mono')
    ..addFont(_read(directory, 'DejaVuSansMono.ttf'))
    ..addFont(_read(directory, 'DejaVuSansMono-Bold.ttf'));

  final loads = <Future<void>>[ui.load(), mono.load()];

  // Material icons are not bundled with the app assets; flutter_test does not
  // load them either, so without this every `Icon` renders as a tofu box in a
  // golden. The font ships with the Flutter SDK.
  final iconFont = _materialIconsFont();
  if (iconFont != null) {
    final icons = FontLoader('MaterialIcons')..addFont(_readFile(iconFont));
    loads.add(icons.load());
  }

  await Future.wait(loads);
}

File? _materialIconsFont() {
  final roots = <String>[
    if (Platform.environment['FLUTTER_ROOT'] case final String root) root,
    if (Platform.environment['HOME'] case final String home)
      '$home/.local/flutter',
    '/opt/flutter',
  ];
  for (final root in roots) {
    final file = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (file.existsSync()) {
      return file;
    }
  }
  return null;
}

Future<ByteData> _readFile(File file) async {
  final bytes = await file.readAsBytes();
  return ByteData.sublistView(bytes);
}

Directory? _fontDirectory() {
  for (final path in <String>[
    'assets/fonts',
    '../../assets/fonts',
    '../assets/fonts',
  ]) {
    final directory = Directory(path);
    if (directory.existsSync()) {
      return directory;
    }
  }
  return null;
}

Future<ByteData> _read(Directory directory, String file) async {
  final bytes = await File('${directory.path}/$file').readAsBytes();
  return ByteData.sublistView(bytes);
}
