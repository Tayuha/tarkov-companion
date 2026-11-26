# Local diagnostics and logs

Tarkov Companion writes diagnostics **locally** so a user can report a problem without an account, a
crash service, or a network round trip. Nothing is uploaded automatically: the app never sends a log,
never includes one in a data request, and has no crash-reporting SDK. Sharing is always an explicit user
action on a file the user chose to create.

The implementation lives in `tarkov_companion_data` under
[`lib/src/logging/`](../app/packages/data/lib/src/logging/):

| File | Role |
|---|---|
| `log_level.dart` | `LogLevel` (`debug`, `info`, `warn`, `error`) and severity ordering |
| `log_record.dart` | `LogRecord`: UTC timestamp, level, message, optional context map |
| `log_sink.dart` | `LogSink` interface (`write`, `close`) |
| `logger.dart` | `Logger` facade with minimum-level filtering and the no-throw guarantee |
| `rotating_file_log_sink.dart` | Line-delimited JSON file sink with rotation and retention |
| `log_export.dart` | `exportLogs(...)`, the ZIP export seam used by the shell |

The data package is pure Dart and performs no network I/O in this layer. The shell chooses the log
directory (the per-user application data directory) and, later, the export destination through the
platform file picker. No UI is wired yet; `exportLogs` is the API the app-shell task will call.

## What is logged

Diagnostics describe **the app's own behavior**, not the user's game:

- lifecycle events: startup, shutdown, recovery mode entered, migration started/finished;
- sync outcomes: mode, dataset name, HTTP status, byte counts, checksum match/mismatch, applied
  version, last-check time;
- feature failures: image cache misses and evictions, database open failures, parse errors with the
  offending field path;
- unhandled errors: exception type, message, and a stack trace, recorded where the error was caught;
- log rotation events, if the sink reports them.

Context values are short and structured: identifiers, counts, status codes, durations, and booleans.
Messages are one line; JSON escaping handles newlines.

## What is deliberately never logged

Logs are treated as potentially shareable with a maintainer, so they must not contain anything that
identifies or affects a player:

- **No tokens, cookies, API keys, or authorization headers.** The client stores none, and the HTTP
  layer never logs request headers.
- **No player progress or profile contents** — no quest states, objective counts, player level, or
  profile names.
- **No personal data** — no account, email, IP address, device identifier, or OS username. Paths are
  reduced to their app-relative or file-name form rather than the full home-directory path.
- **No free-text user input** — search queries and filter text are not logged.
- **No full upstream payloads or bundle contents.** Errors record the dataset name and field path, not
  the document.
- **No remote addresses beyond the documented host allowlist.** A failed request logs `github.com`
  (the allowlisted host), never a URL with query parameters or credentials.

If a future feature needs a value that could fall in one of these categories, log the fact (for example
"price history fetch failed") and not the value.

## On-disk format

Each record is one JSON object followed by `\n`, appended to `<log dir>/app.log`:

```json
{"timestamp":"2026-11-26T15:04:05.123Z","level":"info","message":"manifest checked","context":{"mode":"regular","status":304}}
```

| Field | Type | Notes |
|---|---|---|
| `timestamp` | string | UTC, ISO-8601 with `Z`; records are normally written in order |
| `level` | string | `debug`, `info`, `warn`, or `error` |
| `message` | string | Short, single-line description |
| `context` | object | Optional; omitted when empty. Non-JSON values are stringified so encoding never fails |

The key names are a compatibility surface. Renaming one is a breaking change to the diagnostics format;
support tooling and the export tests read them directly.

## Rotation and retention

Defaults:

| Setting | Default | Meaning |
|---|---|---|
| `maxBytes` | 1 MiB (1,048,576) | Size of `app.log` before it rotates |
| `maxFiles` | 5 | Files kept **including** the current one |

Before a write that would push `app.log` past `maxBytes`, the sink rotates:

```
app.log       -> app.1.log
app.1.log     -> app.2.log
...
app.4.log     -> deleted (oldest)
```

`maxFiles: 5` therefore keeps `app.log`, `app.1.log`, `app.2.log`, `app.3.log`, and `app.4.log`: at most
about 5 MiB of diagnostics. `maxFiles: 1` keeps only the current file and deletes it on rotation. Files
older than the cap are always removed, never renamed beyond it, so the retained set has a hard bound.

A single record larger than `maxBytes` is not dropped and does not loop: the sink rotates first, then
writes the oversized line as the new current file. The next write rotates it out.

The sink creates the directory on first write, appends with `flush: true`, and **closes the file after
every line**. No handle is held between writes, which matters on Windows where an open handle would
block deletion or export. Concurrent `Logger` calls are serialized through an internal queue, so lines
are written whole and never interleave.

## Export

`exportLogs` turns the current log set into one ZIP:

```dart
final result = await exportLogs(
  logDir: logDir,
  destination: File('C:/Users/me/Desktop/tarkov-diagnostics.zip'),
  appVersion: '0.1.0',
);
```

Archive layout:

```
logs/app.log
logs/app.1.log
...
metadata.json
```

`metadata.json` is a small, human-readable document:

```json
{
  "format": "tarkov-companion.logs",
  "formatVersion": 1,
  "exportedAt": "2026-11-26T15:04:05.123Z",
  "appVersion": "0.1.0",
  "logFiles": ["logs/app.log", "logs/app.1.log"]
}
```

`appVersion` is present only when the caller supplies it. `logFiles` lists exactly the entries written
under `logs/`.

Edge cases are intentional:

- A missing log directory, or no logs at all, still produces a valid ZIP containing `metadata.json`, so
  a support request can always attach something.
- Only `app.log` and `app.<n>.log` are exported. Unrelated files next to them are ignored.
- A file that disappears between listing and reading (a concurrent rotation) is skipped; the archive
  stays valid.
- The destination's parent directory is created if needed, and the file is flushed to disk before
  `exportLogs` returns.

`exportLogs` performs filesystem I/O only. It does not open a socket, does not read app settings, and
does not upload anything. The archive belongs to the user and moves only when the user moves it.

## Failure behavior

Logging is best effort. `Logger.log` (and its `debug`/`info`/`warn`/`error` helpers) never completes
with an error, including when:

- the sink throws synchronously;
- the sink returns a rejected future;
- the log directory is missing, is actually a file, or is not writable;
- the disk is full or the file cannot be opened.

`RotatingFileLogSink` additionally swallows its own I/O errors, and a record that cannot be JSON-encoded
is dropped. A broken log must not crash the app it is meant to diagnose, and an asynchronous write
failure must never surface as an unhandled error.

## Verifying

From `app/`:

```bash
dart test packages/data/test/logging
flutter analyze
dart run tool/check_architecture.dart
```

The tests cover the format below the threshold, rotation at the byte boundary, retention pruning,
single-file mode, oversized records, concurrent writes, a broken directory, the no-throw guarantee,
and ZIP export both with logs and with none. They use temporary directories only.

The privacy claim is auditable: see [`network.md`](network.md) for the host allowlist and
`check_architecture.dart` for the dependency boundary that keeps this layer free of Flutter and network
code.
