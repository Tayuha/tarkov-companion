import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

/// A save/open dialog seam for progress files.
///
/// Production uses [PlatformProgressFilePicker]. Tests use a
/// [DirectoryProgressFilePicker], which returns deterministic paths inside a
/// temporary directory without touching a platform channel. Keeping the picker
/// behind this interface is what makes the export/import screens testable.
abstract interface class ProgressFilePicker {
  /// Asks for a destination for an export, or returns `null` when cancelled.
  Future<String?> chooseSavePath({required String suggestedName});

  /// Asks for a progress file to import, or returns `null` when cancelled.
  Future<String?> chooseOpenPath();
}

/// The platform file dialog, backed by `file_selector`.
///
/// This is the only unverified seam in the export flow: widget tests never open
/// a native dialog. The file contents and the save path handling around it are
/// covered by the temp-directory tests.
final class PlatformProgressFilePicker implements ProgressFilePicker {
  const PlatformProgressFilePicker();

  static const XTypeGroup _jsonFiles = XTypeGroup(
    label: 'Progress export',
    extensions: <String>['json'],
  );

  @override
  Future<String?> chooseSavePath({required String suggestedName}) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const <XTypeGroup>[_jsonFiles],
    );
    return location?.path;
  }

  @override
  Future<String?> chooseOpenPath() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_jsonFiles],
    );
    return file?.path;
  }
}

/// A picker that resolves names inside one directory.
///
/// Used by tests and by any future headless export flow. [savePath] can force
/// an exact destination; [importPath] can point at an existing fixture.
final class DirectoryProgressFilePicker implements ProgressFilePicker {
  DirectoryProgressFilePicker(this.directory, {this.savePath, this.importPath});

  final Directory directory;
  final String? savePath;
  final String? importPath;

  @override
  Future<String?> chooseSavePath({required String suggestedName}) async {
    return savePath ?? p.join(directory.path, suggestedName);
  }

  @override
  Future<String?> chooseOpenPath() async => importPath;
}
