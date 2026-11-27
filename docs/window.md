# Desktop window and single instance

The Linux desktop shell keeps its window usable across restarts and refuses to
run two database writers at once. Both behaviors live in `app/lib/src/` and the
GTK runner in `app/linux/runner/my_application.cc`.

## Window geometry

### Policy

`WindowGeometry` (`app/lib/src/window_geometry.dart`) is pure Dart and owns every
rule:

| Rule | Value |
|---|---|
| Minimum size | 800 × 560 logical pixels |
| First-launch size | 1280 × 720, centered in the primary work area |
| Saved rectangle | Restored inside the monitor it overlaps most |
| Off-screen rectangle | Clamped into the primary monitor |
| Oversized rectangle | Shrunk to the monitor work area |
| Undersized rectangle | Grown to the minimum size |

Work areas come from GTK (`GdkMonitor` work area), so panels and docks are
excluded. A window last used on a second monitor reopens there; if that monitor
is gone, it reopens on the primary monitor.

### Persistence

The rectangle is stored in the existing settings table under the additive key
`settings.windowGeometry`, as a JSON document:

```json
{"x": 320.0, "y": 160.0, "width": 1280.0, "height": 720.0}
```

`SettingsRepository.readWindowGeometryJson()` and `setWindowGeometryJson()`
own the row; the regular settings write keeps the key because it is part of
`AppSettingKeys.all`. Missing, corrupt, or non-positive geometry is treated as
"no saved rectangle".

### Flow

1. `WindowGeometryBinder.start()` registers the close handshake and subscribes
   to move/resize events.
2. After the session opens, `bind()` reads the saved rectangle, calls GTK for
   the current work areas, clamps the rectangle, and applies it.
3. GTK emits `windowGeometryChanged` on every configure event. Dart debounces
   for 500 ms before writing, so a drag produces one write.
4. Closing the window sends `windowClosing` with the final rectangle. Dart
   saves it and calls the `close` method; the runner has a 3 s fallback so a
   dead isolate cannot make the window unclosable.

### Platform channel

Channel: `dev.tarkovcompanion/window`.

| Direction | Method | Payload |
|---|---|---|
| Dart → GTK | `getMetrics` | `null`; returns `{window, workAreas, primaryIndex}` |
| Dart → GTK | `setGeometry` | `{x, y, width, height}` |
| Dart → GTK | `focus` | `null`; presents the window |
| Dart → GTK | `close` | `null`; destroys the window |
| GTK → Dart | `windowGeometryChanged` | `{x, y, width, height}` |
| GTK → Dart | `windowClosing` | `{x, y, width, height}` |

The runner also installs a GTK minimum-size hint (800 × 560 align with the Dart
constants). On Wayland the compositor may ignore `gtk_window_move`, so position
restoration is best effort there; size and clamping still apply.

## Single instance

### Lock and message path

The first process owns `instance.lock` under the runtime directory
(`$XDG_RUNTIME_DIR/tarkov_companion`, falling back to
`<data-root>/run` when the variable is unset). The lock file holds the owner
PID and is created with `File.create(exclusive: true)`, so creating it is
atomic across processes. A lock whose PID no longer exists in `/proc` is
stale and is reclaimed.

The primary then binds `instance.sock` in the same directory. A later launch:

1. fails to create the lock,
2. reads the live owner PID,
3. connects to the socket,
4. writes one newline-delimited JSON message,
5. closes the connection and calls `exit(0)` **before** `openAppSession`.

The message is `{"type":"focus","itemId":"<id>"}`; `itemId` is omitted for a
plain launch. The primary calls the runner's `focus` method and queues the item
id as a deep link. Because the second process exits before the database opens,
the SQLite writer is never duplicated.

### Manual check

With a built debug bundle:

```sh
cd app
./build/linux/x64/debug/bundle/tarkov_companion &
sleep 2
./build/linux/x64/debug/bundle/tarkov_companion
```

Expected: only one window remains, it is focused, and exactly one process is
alive:

```sh
pgrep -fa bundle/tarkov_companion
```

A unit test cannot exercise two OS processes; `app/test/single_instance_test.dart`
covers the lock states and the socket message path in one process, including a
stale lock file, a stale socket file, and a live owner with no listener.
