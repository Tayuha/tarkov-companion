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

  await Future.wait(<Future<void>>[ui.load(), mono.load()]);
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
