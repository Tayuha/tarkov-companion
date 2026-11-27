import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One message sent from a second launch to the running instance.
final class InstanceMessage {
  const InstanceMessage({this.itemId});

  /// The item to open, or `null` when the launch only asks for focus.
  final String? itemId;

  /// The JSON object written to the instance socket.
  Map<String, Object?> toJson() => {
    'type': 'focus',
    if (itemId != null) 'itemId': itemId,
  };

  /// Parses one newline-delimited socket message; malformed input is ignored.
  static InstanceMessage? tryParse(String line) {
    if (line.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map || decoded['type'] != 'focus') {
        return null;
      }
      final itemId = decoded['itemId'];
      if (itemId != null && itemId is! String) {
        return null;
      }
      final cleaned = (itemId as String?)?.trim();
      return InstanceMessage(
        itemId: cleaned == null || cleaned.isEmpty ? null : cleaned,
      );
    } on FormatException {
      return null;
    }
  }
}

/// The Linux single-instance guard.
///
/// The first process atomically creates `instance.lock` in the runtime
/// directory (normally `$XDG_RUNTIME_DIR/tarkov_companion`) and listens on
/// `instance.sock`. The lock file holds the owner PID, so a lock left by a
/// crashed process is recognised as stale through `/proc`.
///
/// A second process sees a live owner, connects to the socket, writes one
/// [InstanceMessage] line, and exits before the database is opened. The socket
/// is only a message path; the exclusive lock file is what prevents two
/// database writers.
final class SingleInstance {
  SingleInstance._primary(this._server, this._socketPath, this._lockPath)
    : isPrimary = true;

  SingleInstance._secondary()
    : isPrimary = false,
      _server = null,
      _socketPath = '',
      _lockPath = '';

  /// Whether this process owns the window and may open the database.
  final bool isPrimary;

  /// Emits every message received from a later launch.
  final StreamController<InstanceMessage> _messages =
      StreamController<InstanceMessage>();

  final ServerSocket? _server;
  final String _socketPath;
  final String _lockPath;

  /// Messages from later launches. A single-subscription stream buffers events
  /// until the app shell listens.
  Stream<InstanceMessage> get messages => _messages.stream;

  /// Acquires the instance slot under [directory].
  ///
  /// When this is a secondary process and [message] is supplied, the message
  /// is forwarded before the returned future completes. Callers must exit
  /// without opening the database when [isPrimary] is false.
  static Future<SingleInstance> acquire({
    required Directory directory,
    InstanceMessage? message,
    Duration startupTimeout = const Duration(seconds: 2),
  }) async {
    await directory.create(recursive: true);
    final socketPath = '${directory.path}/instance.sock';
    final lockPath = '${directory.path}/instance.lock';
    final lockFile = File(lockPath);
    final deadline = DateTime.now().add(startupTimeout);

    while (true) {
      if (await _claimLock(lockFile)) {
        final socket = File(socketPath);
        try {
          if (await socket.exists()) {
            await socket.delete();
          }
        } on FileSystemException {
          // Bind below reports the real problem if the path is still unusable.
        }
        final server = await ServerSocket.bind(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
        );
        final instance = SingleInstance._primary(server, socketPath, lockPath);
        instance._acceptConnections();
        return instance;
      }

      final owner = await _readOwner(lockFile, deadline: deadline);
      if (owner != null && await _processAlive(owner)) {
        final connection = await _connect(socketPath, deadline: deadline);
        if (connection == null) {
          throw StateError(
            'Another Tarkov Companion instance (pid $owner) holds the runtime '
            'lock but is not accepting connections at $socketPath.',
          );
        }
        await _forward(connection, message);
        return SingleInstance._secondary();
      }

      // The owner is gone (or the PID was never written): remove the stale
      // lock and socket, then try to become the primary.
      await _deleteQuietly(lockFile);
      await _deleteQuietly(File(socketPath));
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
          'Could not acquire the Tarkov Companion runtime lock at $lockPath.',
        );
      }
    }
  }

  /// Releases the socket and the instance lock.
  Future<void> close() async {
    if (_messages.hasListener) {
      await _messages.close();
    } else {
      // A controller without a listener never completes its done future.
      unawaited(_messages.close());
    }
    final server = _server;
    if (server != null) {
      await server.close();
      // Order matters: remove the socket, then the lock. A later process can
      // only claim the lock after this process stops advertising its socket.
      await _deleteQuietly(File(_socketPath));
      await _deleteQuietly(File(_lockPath));
    }
  }

  void _acceptConnections() {
    _server!.listen((connection) {
      connection
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              final message = InstanceMessage.tryParse(line);
              if (message != null && !_messages.isClosed) {
                _messages.add(message);
              }
            },
            onError: (Object _) => connection.destroy(),
            onDone: () => connection.destroy(),
          );
    });
  }

  /// Atomically creates and populates the lock file.
  static Future<bool> _claimLock(File lockFile) async {
    try {
      await lockFile.create(exclusive: true);
    } on FileSystemException {
      return false;
    }
    try {
      await lockFile.writeAsString('$pid\n');
      return true;
    } on FileSystemException {
      await _deleteQuietly(lockFile);
      return false;
    }
  }

  static Future<int?> _readOwner(
    File lockFile, {
    required DateTime deadline,
  }) async {
    while (true) {
      try {
        final pid = int.tryParse((await lockFile.readAsString()).trim());
        if (pid != null) {
          return pid;
        }
      } on FileSystemException {
        return null;
      }
      if (DateTime.now().isAfter(deadline)) {
        return null;
      }
      // The winner may have created the file but not written its PID yet.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  static Future<bool> _processAlive(int owner) async {
    if (owner <= 0) {
      return false;
    }
    try {
      if (!await Directory('/proc').exists()) {
        // Without procfs the liveness check is unavailable; assume live to
        // avoid starting a second database writer.
        return true;
      }
      return await Directory('/proc/$owner').exists();
    } on FileSystemException {
      return false;
    }
  }

  static Future<Socket?> _connect(
    String socketPath, {
    required DateTime deadline,
  }) async {
    while (true) {
      try {
        return await Socket.connect(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
          timeout: const Duration(milliseconds: 250),
        );
      } on SocketException {
        if (DateTime.now().isAfter(deadline)) {
          return null;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  static Future<void> _forward(
    Socket connection,
    InstanceMessage? message,
  ) async {
    try {
      // A later launch always asks for focus, even without an item.
      connection.write(
        '${jsonEncode((message ?? const InstanceMessage()).toJson())}\n',
      );
      await connection.flush();
    } finally {
      await connection.close();
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Best effort: a stale entry is cleaned by the next launch.
    }
  }
}
