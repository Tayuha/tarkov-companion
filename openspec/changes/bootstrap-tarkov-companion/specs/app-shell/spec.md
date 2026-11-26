# Spec Delta

## Purpose

Defines how the application behaves as a desktop program: first-run data bootstrap, non-blocking startup,
update handling, offline and failure states, window behavior, distribution, and its privacy posture.

## ADDED Requirements

### Requirement: First-run bootstrap

On first run the app SHALL download the initial dataset with visible progress, an estimate of download
size, the ability to cancel, and enough explanation that the wait is expected rather than a hang.

#### Scenario: Successful first download

- **WHEN** the user completes the first-run download
- **THEN** the app opens the catalog with the active game mode's dataset and records the sync time

#### Scenario: Cancelled first download

- **WHEN** the user cancels the first-run download
- **THEN** the app explains that browsing needs data, offers retry and a smaller data option if available, and does not show a broken catalog

#### Scenario: Download fails midway

- **WHEN** the first-run download fails
- **THEN** the app reports the failure, keeps any verified partial progress, and offers retry without restarting the app

### Requirement: Startup never blocks on the network

The app SHALL open using the last applied dataset and SHALL perform update checks in the background, so
startup time does not depend on connectivity.

#### Scenario: Normal start with data present

- **WHEN** the app starts and a dataset exists
- **THEN** the main interface is interactive before any network request completes

#### Scenario: Data update available at startup

- **WHEN** an update is found shortly after launch
- **THEN** the update proceeds in the background with a non-modal indicator and no forced restart

### Requirement: Update check controls

The app SHALL support automatic update checks on a configurable schedule, a manual "check now" action,
and a preference to suppress automatic checks, and SHALL report the last check time and outcome.

#### Scenario: Manual check

- **WHEN** the user triggers a manual check and data is current
- **THEN** the app reports that data is up to date with the check timestamp

#### Scenario: Automatic checks disabled

- **WHEN** the user disables automatic checks
- **THEN** the app performs no background data or app-update requests until the user acts manually

### Requirement: Offline and degraded states

Every network-dependent screen SHALL have an explicit offline or error state that keeps locally available
content usable and offers a retry.

#### Scenario: Price history while offline

- **WHEN** the user requests content that requires the network while offline
- **THEN** the app states that the content needs a connection, shows cached data if present, and offers retry

#### Scenario: Upstream outage

- **WHEN** the data source returns server errors
- **THEN** the app keeps current data and reports the outage without blocking navigation

### Requirement: Desktop window behavior

The desktop application SHALL enforce a minimum usable window size, remember size and position between
sessions, allow a single running instance to be focused rather than duplicated, and support keyboard
navigation of the primary lists.

#### Scenario: Reopen after resize

- **WHEN** the user resizes and repositions the window, then restarts the app
- **THEN** the window reopens at the previous size and position, clamped to the visible display area

#### Scenario: Second launch

- **WHEN** the user launches the app while it is already running
- **THEN** the existing window is focused instead of a second instance starting

#### Scenario: Keyboard-only browsing

- **WHEN** the user navigates the catalog and quest lists using only the keyboard
- **THEN** focus order is visible, selection is reachable, and no action requires a pointer

### Requirement: Release packaging

The project SHALL produce a versioned Linux artifact for the first release: an AppImage that runs without
installation, or a `.deb` that installs and registers an uninstaller, and SHALL display the application
version in the UI. Windows and mobile packaging are deferred until the Linux build is approved.

#### Scenario: Per-user install

- **WHEN** a user runs the AppImage on a clean Linux system
- **THEN** the app launches without installation or administrator rights

#### Scenario: Version visibility

- **WHEN** the user opens the about screen
- **THEN** the app version, data bundle version, and dataset age are shown

### Requirement: Signed, verifiable builds

Release artifacts SHALL be published with checksums and, where signing is configured, SHALL be signed so
users can verify the installer's origin, and the release notes SHALL state whether a build is signed.

#### Scenario: Signature not configured

- **WHEN** a release is produced without code signing
- **THEN** the release notes state that the artifact is unsigned and explain how to verify its checksum

#### Scenario: Checksum published

- **WHEN** a release is published
- **THEN** the checksum of the installer is listed alongside the download

### Requirement: Privacy by default

The application SHALL NOT collect telemetry, analytics, or usage data, and SHALL make network requests only
to a documented allowlist of data and update endpoints.

#### Scenario: Network request audit

- **WHEN** a maintainer reviews the app's network calls
- **THEN** every call targets a host listed in the project documentation, with no third-party analytics or crash reporting endpoints

#### Scenario: No account required

- **WHEN** a user installs and uses the app
- **THEN** no sign-in, email, or personal information is requested at any point

### Requirement: Local diagnostics

The app SHALL write diagnostics locally with rotation, SHALL NOT upload them automatically, and SHALL let
the user export or reveal the log file when reporting a problem.

#### Scenario: Export logs

- **WHEN** the user chooses to export diagnostics
- **THEN** a log archive is written to a user-chosen location and the app confirms the path

#### Scenario: Crash

- **WHEN** the app encounters an unhandled error
- **THEN** it records the error locally, shows a recoverable message where possible, and offers the diagnostics export without sending anything
