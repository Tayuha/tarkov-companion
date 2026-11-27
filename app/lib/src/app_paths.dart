import 'dart:io';

/// The per-user data directory used by the Linux desktop app.
///
/// Resolution deliberately avoids `path_provider`: the first release target is
/// Linux, where the XDG base-directory convention is the documented location.
///
/// ```
/// $XDG_DATA_HOME/tarkov_companion       (when set)
/// $HOME/.local/share/tarkov_companion   (otherwise)
///   db/tarkov_companion.sqlite
///   logs/app.log, app.1.log, ...
///   downloads/<mode>/<dataset>.jsonl.zst
/// ```
///
/// [resolve] is a pure function over the supplied environment, so the app test
/// can assert both branches without touching the real home directory.
final class AppPaths {
  const AppPaths(this.root);

  /// The `tarkov_companion/` directory itself.
  final Directory root;

  /// Resolves the data root from the process environment.
  ///
  /// [environment] exists for tests; production omits it.
  factory AppPaths.resolve({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final xdgDataHome = env['XDG_DATA_HOME']?.trim();
    final Directory base;
    if (xdgDataHome != null && xdgDataHome.isNotEmpty) {
      base = Directory(xdgDataHome);
    } else {
      final home = env['HOME']?.trim();
      if (home == null || home.isEmpty) {
        throw StateError(
          'Neither XDG_DATA_HOME nor HOME is set; cannot choose a data '
          'directory.',
        );
      }
      base = Directory(_join(home, '.local', 'share'));
    }
    return AppPaths(Directory(_join(base.path, 'tarkov_companion')));
  }

  /// Holds the SQLite database and its pre-migration backups.
  Directory get databaseDirectory => Directory(_join(root.path, 'db'));

  /// Holds the rotating diagnostic log files.
  Directory get logsDirectory => Directory(_join(root.path, 'logs'));

  /// Holds verified per-mode dataset files.
  Directory get downloadsDirectory => Directory(_join(root.path, 'downloads'));

  /// Holds cached item artwork, bounded by the image cache budget.
  Directory get imagesDirectory => Directory(_join(root.path, 'cache', 'images'));

  /// Holds the single-instance lock and socket.
  ///
  /// Prefers `$XDG_RUNTIME_DIR/tarkov_companion`, the per-user, tmpfs runtime
  /// location on Linux. When the variable is unset it falls back to `run/` in
  /// the data root so two processes on one machine still share one lock.
  Directory get runtimeDirectory => runtimeDirectoryFrom(Platform.environment);

  /// Resolves the runtime directory from [environment].
  ///
  /// [environment] exists for tests; production uses the process environment.
  Directory runtimeDirectoryFrom(Map<String, String> environment) {
    final xdgRuntime = environment['XDG_RUNTIME_DIR']?.trim();
    if (xdgRuntime != null && xdgRuntime.isNotEmpty) {
      return Directory(_join(xdgRuntime, 'tarkov_companion'));
    }
    return Directory(_join(root.path, 'run'));
  }

  /// The database file path.
  String get databasePath =>
      _join(databaseDirectory.path, 'tarkov_companion.sqlite');

  /// Creates the root directory. Child directories are created lazily by the
  /// database, logger, and downloader.
  Future<void> ensureCreated() async {
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
  }

  static String _join(String first, String second, [String? third]) {
    final separator = Platform.pathSeparator;
    final base = first.endsWith(separator)
        ? first.substring(0, first.length - separator.length)
        : first;
    final middle = second.startsWith(separator) ? second : '$separator$second';
    final value = '$base$middle';
    if (third == null) {
      return value;
    }
    return '$value$separator'
        '${third.startsWith(separator) ? third.substring(separator.length) : third}';
  }
}
