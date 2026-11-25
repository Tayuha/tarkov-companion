# Spec Delta

## Purpose

Keeps a complete, versioned copy of the Escape from Tarkov game dataset on the user's device so the app
stays fast and fully usable without a live connection, while updating incrementally when data changes.

## ADDED Requirements

### Requirement: Versioned data bundles

The system SHALL publish one data bundle per game mode (`regular`, `pve`, `pvp-season`), each carrying a
bundle schema version, a dataset version, a generation timestamp, and the upstream source timestamps it
was built from. A bundle SHALL be self-describing enough for a client to decide whether it can consume it
without downloading it.

#### Scenario: Bundle advertises its identity

- **WHEN** a client reads the bundle manifest
- **THEN** it receives the bundle schema version, dataset version, generation time, per-dataset sizes and checksums, and the minimum supported app data-schema version

#### Scenario: Unsupported bundle is refused

- **WHEN** the manifest declares a bundle schema version newer than the client supports
- **THEN** the client keeps its current data, reports that an app update is required, and does not partially apply the bundle

### Requirement: Incremental download

The client SHALL avoid re-downloading unchanged datasets by comparing the local dataset versions and
checksums against the manifest, and SHALL support conditional requests so an unchanged manifest costs a
single small response.

#### Scenario: Nothing changed upstream

- **WHEN** the client checks for updates and the manifest checksum matches the last stored manifest
- **THEN** no dataset payload is downloaded and the last-checked timestamp is recorded

#### Scenario: One dataset changed

- **WHEN** only the tasks dataset checksum differs from the stored value
- **THEN** the client downloads only the tasks dataset and leaves items, maps, traders, hideout, crafts, and barters untouched

### Requirement: Integrity verification

Every downloaded dataset SHALL be verified against its manifest checksum before it becomes readable by
the application. A dataset that fails verification SHALL be discarded and SHALL NOT replace previously
working data.

#### Scenario: Corrupted download is rejected

- **WHEN** a downloaded dataset's computed checksum does not match the manifest
- **THEN** the client discards it, keeps serving the previous dataset, and reports a recoverable sync error

### Requirement: Atomic dataset activation

A dataset update SHALL become visible to the app only after it has been fully written and verified, so a
crash or power loss mid-update cannot leave a mixed-version database.

#### Scenario: Update interrupted

- **WHEN** the app is terminated while writing a new dataset
- **THEN** the next start uses the last fully applied dataset version and discards the incomplete one

#### Scenario: Rollback after failed apply

- **WHEN** applying a verified dataset fails partway through
- **THEN** the client restores the previous dataset version and reports the failure without losing player progress

### Requirement: Scheduled upstream refresh

The project SHALL run an automated pipeline that fetches the upstream endpoints, validates their shape,
normalizes them into bundles, and publishes new versions when the upstream content changes. The schedule
SHALL keep data fresher than 24 hours under normal upstream availability.

#### Scenario: Upstream unchanged

- **WHEN** the pipeline runs and the upstream payload hashes match the last successful build
- **THEN** it publishes no new bundle and records a successful no-op run

#### Scenario: Upstream schema drift

- **WHEN** a required field is missing or changes type in an upstream payload
- **THEN** the pipeline fails the build, keeps the last good bundle published, and surfaces a failure notification to maintainers

### Requirement: Offline operation

The application SHALL remain fully usable for browsing items, quests, and stored prices using the last
applied dataset when no network is available, and SHALL communicate how old that data is.

#### Scenario: Launch without connectivity

- **WHEN** the app starts with no network and a previously applied dataset exists
- **THEN** the catalog and quest tracker open normally and the UI shows the dataset's age and last successful sync time

#### Scenario: First launch without connectivity

- **WHEN** the app starts with no network and no dataset exists
- **THEN** the app explains that an initial download is required, offers a retry, and does not present an empty or broken catalog

### Requirement: Price freshness is distinct from catalog freshness

Item price fields SHALL display the timestamp of the last price observation, and price data older than the
configured threshold SHALL be labelled as stale rather than presented as current.

#### Scenario: Stale prices are labelled

- **WHEN** the newest price observation for an item is older than the freshness threshold
- **THEN** the item shows the observation time and a stale indicator instead of an unqualified price

### Requirement: Update traffic respects user constraints

Automatic data updates SHALL be pausable, SHALL respect a metered-connection preference, and SHALL never
block app startup or interrupt an in-progress interaction.

#### Scenario: Metered connection

- **WHEN** the device reports a metered connection and automatic updates are restricted
- **THEN** the client skips the download, keeps current data, and offers a manual update action

#### Scenario: Update during use

- **WHEN** an update is applied while the user is browsing
- **THEN** the current view stays responsive and the new data appears without losing the user's place
