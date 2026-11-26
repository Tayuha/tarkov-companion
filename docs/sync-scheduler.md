# Background update scheduler

`SyncScheduler` in `tarkov_companion_data`
(`app/packages/data/lib/src/sync/scheduler.dart`) decides **when** an update
check may run. It does not download or ingest anything: the check itself is an
injected `SyncRunner`, so the policy can be tested with a fake clock, fake
timers and fake monitors, and the data package stays pure Dart.

The scheduler is the client-side half of the
[update traffic requirement](../openspec/changes/bootstrap-tarkov-companion/specs/data-sync/spec.md)
and feeds the update-check controls in the shell (task 8.3: schedule, manual
check, last check time/outcome).

## Injected dependencies

| Dependency | Purpose |
|---|---|
| `SettingsRepository` | Reads `autoUpdateEnabled` and `allowMeteredUpdates` before every decision. |
| `SyncClock` (`DateTime Function()`) | All decisions, recorded check times and retry times use this clock. |
| `SyncTimerFactory` | Creates the one-shot timer for the next check; defaults to `Timer.new`. |
| `NetworkMonitor` | `isOnline`, `isMetered`, and a `changes` stream for either value. |
| `VisibilityMonitor` | `isForeground` and a `changes` stream. |
| `SyncRunner` | Performs one check and completes when it succeeded or threw. |
| `SyncStateStore` | Reads and records the last successful check time. |

`SyncPolicy` tunes the intervals; its defaults are in the table below.

The Flutter shell supplies the real implementations later, backed by its
connectivity plugin and window lifecycle. Nothing in this file imports
`package:flutter` or opens a socket.

## Policy

`checkNow({manual: false})` returns one typed `SyncDecision`. A manual check
only requires a connection; an automatic check applies every rule in order.

| Priority | Condition | Decision | `nextRunAt` |
|---|---|---|---|
| — | **Manual**, offline | `skippedOffline` | `null` (wait for a network change) |
| — | **Manual**, online | `ran` or `failed` | interval or retry time |
| 1 | `autoUpdateEnabled` is `false` | `skippedAutoUpdateDisabled` | `null` until the user checks manually |
| 2 | The app is in the background | `skippedBackground` | `null` (wait for foreground) |
| 3 | Offline | `skippedOffline` | `null` (wait for a network change) |
| 4 | Metered connection and `allowMeteredUpdates` is `false` | `skippedMetered` | `null` (wait for a connection change) |
| 5 | A failure backoff is still active | `skippedBackoff` | the retry time |
| 6 | The last success is newer than `checkInterval` (6 h) | `skippedNotDue` | `lastCheckedAt + 6 h` |
| — | Otherwise | `ran` or `failed` | `now + 6 h` or the retry time |

A concurrent call returns `skippedInFlight`; it never queues a second check.

`ran` means the runner completed, `recordCheckedAt(clock())` was written and the
failure sequence was reset. `failed` carries the runner's error and a
`retryAt`; a failed check does **not** move the last-check time, so the
"not due" rule never hides a retry.

## Failure backoff

| Consecutive failures | Next attempt after |
|---|---|
| 1 | 15 minutes |
| 2 | 30 minutes |
| 3 | 60 minutes |
| 4 and later | the normal 6-hour interval |

The delay is `backoffBase × 2^(n-1)`, capped at `backoffMax` (2 hours) and
limited to `maxBackoffAttempts` (3) exponential retries. A later success resets
the sequence to zero. The backoff is in memory only: after a restart the
scheduler reads the last successful check time and resumes the normal policy,
which is safe because a failed check changed no data.

`consecutiveFailures`, `lastCheckedAt` and `nextRunAt` are exposed for the
update-status UI and for diagnostics.

## Scheduling and change events

`start()`:

1. subscribes to `NetworkMonitor.changes` and `VisibilityMonitor.changes`;
2. reads the last successful check time;
3. when automatic checks are enabled, the app is foreground and the network is
   online, arms one timer for the next due time (`now` if a check was never
   done, otherwise `lastCheckedAt + 6 h`);
4. otherwise arms nothing and waits for the event that changes the blocking
   condition.

Every network or visibility event re-reads both getters. If the app is
foreground and online, it calls `checkNow()` immediately, so a reconnect or a
return to the foreground is not delayed until the timer tick. The event still
goes through the full policy: an event inside the interval returns
`skippedNotDue`, and a metered or disabled state still blocks the check.

A timer fires at most once: the callback runs one check, and the resulting
decision arms the next timer. `dispose()` cancels the timer and both
subscriptions and is idempotent; a runner already executing finishes but
schedules nothing. `checkNow()` throws `StateError` after disposal.

## Interval versus data freshness

`SyncPolicy.checkInterval` (6 h) is deliberately independent of
`AppSettings.dataFreshnessHours` (24 h by default):

- the pipeline publishes at most every 6 hours, so checking more often than
  that mostly costs conditional `304` requests;
- `dataFreshnessHours` is a **labelling** threshold (when the UI shows data as
  stale), not a network schedule;
- tying them would either make stale labels depend on download timing or hide
  new bundles for up to a day.

Both values are configurable. A future settings extension (a check-frequency
preference) can feed `SyncPolicy` without changing the engine.

## Standalone use

```dart
final scheduler = SyncScheduler(
  settings: settingsRepository,
  stateStore: myStateStore,       // e.g. remoteManifest.lastCheckedAt
  runner: myRunner,               // fetch -> download -> ingest
  network: myNetworkMonitor,      // connectivity plugin adapter
  visibility: myVisibilityMonitor,// window lifecycle adapter
);

await scheduler.start();

final decision = await scheduler.checkNow(manual: true);
// decision.type, decision.retryAt, scheduler.nextRunAt, ...
```

The shell adapts `ManifestFetcher.lastCheckedAt` (or the `remoteManifest` row)
to `SyncStateStore`; the scheduler itself is mode-agnostic. "Sync all modes"
orchestration is intentionally not part of this type, so the runner stays the
single place that knows which modes to process.

## Tests

`app/packages/data/test/sync/scheduler_test.dart` drives a fake clock and a
hand-advanced timer queue; no real time passes and no socket is opened. It
covers:

- all 16 combinations of auto-update on/off, metered allowed/disallowed,
  foreground/background and offline/online;
- an unmetered connection with metered downloads forbidden;
- not due, exactly due, and a timer firing at `lastCheckedAt + 6 h`;
- a manual check bypassing every preference, the interval and an active
  backoff, while still requiring connectivity;
- the 15/30/60-minute backoff sequence, a skip inside the window, the fallback
  to the 6-hour interval, and the reset after a success;
- a network change and a foreground change triggering a due check, and an
  event inside the interval doing nothing;
- `dispose()` cancelling a pending check and ignoring later events;
- `recordCheckedAt` using the injected clock;
- a concurrent call returning `skippedInFlight`.

Run them with:

```bash
cd app
dart test packages/data/test/sync/scheduler_test.dart
```
