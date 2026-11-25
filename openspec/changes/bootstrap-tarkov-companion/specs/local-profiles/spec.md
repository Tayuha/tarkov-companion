# Spec Delta

## Purpose

Owns the player's own data on the device: separate progress per game mode, a portable file format for
backup and transfer, and safe handling of schema changes so progress is never silently lost.

## ADDED Requirements

### Requirement: One profile per game mode

The system SHALL maintain at most one profile for each game mode (`regular`, `pve`, `pvp-season`), SHALL
create a profile on first use of a mode, and SHALL have exactly one active profile at a time.

#### Scenario: First launch

- **WHEN** the app starts with no stored profiles
- **THEN** a regular-game-mode profile is created and activated, and the user can create profiles for other modes explicitly

#### Scenario: Create a PvE profile

- **WHEN** the user activates the PvE mode for the first time
- **THEN** a separate empty PvE profile is created and the regular profile's data is untouched

### Requirement: Editable profile facts

Each profile SHALL let the user record the facts the tracker depends on, at minimum the player's level,
and SHALL apply changes immediately to derived quest availability.

#### Scenario: Level change unlocks quests

- **WHEN** the user raises the profile's player level from 15 to 20
- **THEN** quests whose only unmet requirement was level 20 become available

### Requirement: Profile deletion and reset

The user SHALL be able to delete a profile or reset its progress, with a confirmation that states what
will be lost and that the action cannot be undone.

#### Scenario: Reset progress

- **WHEN** the user confirms resetting the PvE profile
- **THEN** its quest and objective progress is cleared, the profile itself remains, and other profiles are unaffected

#### Scenario: Delete profile

- **WHEN** the user confirms deleting a profile
- **THEN** that profile and its progress are removed and another existing profile becomes active

### Requirement: Portable progress export

The system SHALL export the active profile, or all profiles when requested, to a single JSON file that
includes a format version, app version, export timestamp, profile facts, quest states, and objective
counts, and SHALL NOT include device identifiers or absolute file paths.

#### Scenario: Export to file

- **WHEN** the user exports progress
- **THEN** a JSON file is written to the location the user chooses, and the app reports the item counts it contains

#### Scenario: Export with no progress

- **WHEN** the user exports a profile with no recorded progress
- **THEN** the export succeeds and the file records the profile facts and an empty progress set

### Requirement: Import validation

An import SHALL be rejected as a whole, without modifying stored data, when the file is malformed, has an
unsupported format version, fails its integrity check, or contains identifiers or values outside the
allowed ranges.

#### Scenario: Truncated file

- **WHEN** the user selects a truncated or invalid JSON file
- **THEN** the app reports that the file is not a valid progress export and leaves all profiles unchanged

#### Scenario: Newer format version

- **WHEN** the file's format version is newer than the app supports
- **THEN** the app refuses the import and states that a newer app version is required

### Requirement: Import preview and explicit mode

Before writing anything, an import SHALL show what the file contains and SHALL require the user to choose
between replacing the current profile and merging into it. The default SHALL NOT be a destructive one.

#### Scenario: Replace mode

- **WHEN** the user chooses replace and confirms
- **THEN** the target profile's progress is replaced by the file's progress and the previous state is discarded only after the write succeeds

#### Scenario: Merge mode

- **WHEN** the user chooses merge
- **THEN** quest states present only in the file are added, and for conflicting quests the app reports the conflicts and applies the user's chosen resolution

#### Scenario: Cancel at preview

- **WHEN** the user cancels after previewing an import
- **THEN** no stored data changes

### Requirement: Import is atomic

An import SHALL be applied as a single transaction, so a failure partway through leaves the previous
profile state intact.

#### Scenario: Write failure during import

- **WHEN** the import transaction fails
- **THEN** the profile is unchanged and the app reports the failure with a retry option

### Requirement: Schema migration with recovery

Stored data SHALL be migrated forward through versioned migrations at startup, with a copy of the previous
database retained, and an unrecoverable database SHALL place the app in a read-only recovery state rather
than deleting data.

#### Scenario: Successful migration

- **WHEN** the app starts with a database from an older app version
- **THEN** migrations run, progress remains readable, and the previous database copy is retained

#### Scenario: Failed migration

- **WHEN** a migration fails
- **THEN** the app does not delete the database, offers the retained copy and an export path, and disables writes until resolved

### Requirement: Local-only ownership

Profile data SHALL be stored only on the device, SHALL NOT be transmitted automatically, and SHALL be
removed when the app's data is removed through an explicit in-app action.

#### Scenario: No background upload

- **WHEN** the app performs any data sync or update
- **THEN** the request contains no profile progress, identifiers, or personal data

#### Scenario: Uninstall behavior

- **WHEN** the user uninstalls the application
- **THEN** the project documentation explains where the local database lives and that uninstalling may or may not remove it per platform

### Requirement: Cross-platform portability

An export produced on one supported platform SHALL import successfully on another supported platform
running the same or a newer app version.

#### Scenario: Windows to Android transfer

- **WHEN** a profile exported on Windows is imported on Android
- **THEN** the import validates and restores the same quest and objective progress
