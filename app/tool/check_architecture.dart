// Import-boundary checker for the Flutter client workspace.
//
// Run from `app/`:
//
//   dart run tool/check_architecture.dart
//
// The rule engine (`analyzeSource`) is a pure function over source text, so the
// unit tests can prove that each forbidden edge is reported without adding a
// violating file to the tree.

import 'dart:io';

/// The logical layers of the client package graph.
enum PackageLayer { core, data, features, app }

const _packageNames = <PackageLayer, String>{
  PackageLayer.core: 'tarkov_companion_core',
  PackageLayer.data: 'tarkov_companion_data',
  PackageLayer.features: 'tarkov_companion_features',
  PackageLayer.app: 'tarkov_companion',
};

const _directoryNames = <PackageLayer, String>{
  PackageLayer.core: 'core',
  PackageLayer.data: 'data',
  PackageLayer.features: 'features',
};

/// Allowed `package:` edges. A package may always import itself.
const _allowedImports = <PackageLayer, Set<PackageLayer>>{
  PackageLayer.core: {PackageLayer.core},
  PackageLayer.data: {PackageLayer.core, PackageLayer.data},
  PackageLayer.features: {
    PackageLayer.core,
    PackageLayer.data,
    PackageLayer.features,
  },
  PackageLayer.app: {
    PackageLayer.core,
    PackageLayer.data,
    PackageLayer.features,
    PackageLayer.app,
  },
};

/// Packages that must remain usable without a Flutter engine.
const _flutterFree = {PackageLayer.core, PackageLayer.data};

/// One broken dependency edge.
final class ArchitectureViolation {
  const ArchitectureViolation({
    required this.file,
    required this.line,
    required this.directive,
    required this.uri,
    required this.reason,
  });

  /// Path relative to `app/`, using `/` separators.
  final String file;
  final int line;

  /// `import` or `export`.
  final String directive;
  final String uri;
  final String reason;

  @override
  String toString() => '$file:$line: $directive \'$uri\': $reason';
}

/// The result of checking the whole workspace.
final class WorkspaceReport {
  const WorkspaceReport({required this.filesChecked, required this.violations});

  final int filesChecked;
  final List<ArchitectureViolation> violations;
}

final _directivePattern = RegExp(
  r'''^[ \t]*(import|export)[ \t]+['"]([^'"\r\n]+)['"]''',
  multiLine: true,
);

/// Checks one source file against the dependency rules.
///
/// [filePath] is relative to `app/` and uses `/` separators. Unknown packages
/// (`flutter`, `dart:*`, `test`, ...) are outside the workspace graph and are
/// only checked by the pure-Dart rule.
List<ArchitectureViolation> analyzeSource({
  required PackageLayer layer,
  required String filePath,
  required String source,
}) {
  final violations = <ArchitectureViolation>[];

  for (final match in _directivePattern.allMatches(source)) {
    final directive = match.group(1)!;
    final uri = match.group(2)!;
    final reason = _violationReason(layer, filePath, uri);
    if (reason == null) {
      continue;
    }
    violations.add(
      ArchitectureViolation(
        file: filePath,
        line: _lineAt(source, match.start),
        directive: directive,
        uri: uri,
        reason: reason,
      ),
    );
  }

  return violations;
}

/// Checks every `.dart` file under the app and package `lib/` directories.
WorkspaceReport checkWorkspace(Directory appRoot) {
  var filesChecked = 0;
  final violations = <ArchitectureViolation>[];

  for (final layer in PackageLayer.values) {
    final libDirectory = Directory('${appRoot.path}/${_libRoot(layer)}');
    if (!libDirectory.existsSync()) {
      continue;
    }

    final files =
        libDirectory
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      filesChecked++;
      violations.addAll(
        analyzeSource(
          layer: layer,
          filePath: _relativeTo(appRoot, file),
          source: file.readAsStringSync(),
        ),
      );
    }
  }

  return WorkspaceReport(filesChecked: filesChecked, violations: violations);
}

void main(List<String> arguments) {
  final appRoot = arguments.isEmpty
      ? Directory.current
      : Directory(arguments.single);

  if (!Directory('${appRoot.path}/lib').existsSync()) {
    stderr.writeln(
      'Not an app root: ${appRoot.absolute.path} has no lib/ directory. '
      'Run this from app/.',
    );
    exitCode = 2;
    return;
  }

  final report = checkWorkspace(appRoot);
  if (report.violations.isEmpty) {
    stdout.writeln(
      'Architecture check passed: ${report.filesChecked} files, '
      'no boundary violations.',
    );
    return;
  }

  for (final violation in report.violations) {
    stderr.writeln(violation);
  }
  stderr.writeln(
    'Architecture check failed: ${report.violations.length} violation(s) '
    'in ${report.filesChecked} files.',
  );
  exitCode = 1;
}

String? _violationReason(PackageLayer layer, String filePath, String uri) {
  if (uri.startsWith('package:')) {
    final path = uri.substring('package:'.length);
    final slash = path.indexOf('/');
    final packageName = slash == -1 ? path : path.substring(0, slash);
    final target = _layerForPackageName(packageName);

    if (target == PackageLayer.app && layer != PackageLayer.app) {
      return 'the app shell is not a library; only app may import it';
    }

    if (target != null && !_allowedImports[layer]!.contains(target)) {
      return '${_label(layer)} may not import ${_label(target)}';
    }

    if (packageName == 'flutter' && _flutterFree.contains(layer)) {
      return '${_label(layer)} must stay pure Dart';
    }

    return null;
  }

  if (uri.startsWith('dart:')) {
    if (uri == 'dart:ui' && _flutterFree.contains(layer)) {
      return '${_label(layer)} must stay pure Dart';
    }
    return null;
  }

  final libRoot = _libRoot(layer);
  final resolved = _resolve(fromFile: filePath, uri: uri);
  if (resolved != libRoot && !resolved.startsWith('$libRoot/')) {
    return 'relative import escapes $libRoot/; use a package: import across '
        'packages';
  }

  return null;
}

PackageLayer? _layerForPackageName(String packageName) {
  for (final entry in _packageNames.entries) {
    if (entry.value == packageName) {
      return entry.key;
    }
  }
  return null;
}

String _label(PackageLayer layer) => switch (layer) {
  PackageLayer.core => 'core',
  PackageLayer.data => 'data',
  PackageLayer.features => 'features',
  PackageLayer.app => 'app',
};

String _libRoot(PackageLayer layer) => switch (layer) {
  PackageLayer.app => 'lib',
  _ => 'packages/${_directoryNames[layer]}/lib',
};

String _resolve({required String fromFile, required String uri}) {
  final parts = fromFile.split('/')..removeLast();
  for (final segment in uri.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (parts.isEmpty) {
        // Escapes the app root entirely; keep the marker so the caller fails.
        return '../';
      }
      parts.removeLast();
    } else {
      parts.add(segment);
    }
  }
  return parts.join('/');
}

int _lineAt(String source, int offset) {
  var line = 1;
  for (var index = 0; index < offset; index++) {
    if (source.codeUnitAt(index) == 0x0A) {
      line++;
    }
  }
  return line;
}

String _relativeTo(Directory appRoot, File file) {
  final root = _toPosix(appRoot.absolute.path);
  final rootWithSeparator = root.endsWith('/') ? root : '$root/';
  final path = _toPosix(file.absolute.path);
  return path.startsWith(rootWithSeparator)
      ? path.substring(rootWithSeparator.length)
      : path;
}

String _toPosix(String path) => path.replaceAll('\\', '/');
