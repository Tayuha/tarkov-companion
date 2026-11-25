# Spec Delta

## Purpose

Turns the game's quest data into a tracker that shows what a player can do next, what each quest requires,
and what completing it unlocks, while recording the player's own progress locally.

## ADDED Requirements

### Requirement: Quest catalog

The tracker SHALL list all quests in the active dataset and SHALL support search by quest name and
filtering by trader, minimum player level, map, and the player's progress state.

#### Scenario: Filter by trader

- **WHEN** the user filters the catalog to a single trader
- **THEN** only that trader's quests are listed, with the active filter visible

#### Scenario: Search inside a filter

- **WHEN** the user types a quest name while a trader filter is active
- **THEN** results are the intersection of the search term and the filter

### Requirement: Derived quest availability

The tracker SHALL compute, from the active profile and the quest prerequisites, whether each quest is
locked, available, in progress, or completed, and SHALL present locked quests with the specific unmet
requirements.

#### Scenario: Level too low

- **WHEN** a quest requires player level 20 and the active profile records level 15
- **THEN** the quest is shown as locked and names the level requirement as the reason

#### Scenario: Prerequisite quest incomplete

- **WHEN** a quest requires another quest that the profile has not completed
- **THEN** the quest is shown as locked and names the incomplete prerequisite

#### Scenario: All requirements met

- **WHEN** every prerequisite for a quest is satisfied
- **THEN** the quest moves to available without any manual refresh

### Requirement: Quest detail

The quest detail SHALL show the quest's objectives, prerequisites, turn-in requirements, rewards, unlocks,
trader, minimum level, associated maps, and wiki link as provided by the dataset.

#### Scenario: Objective list

- **WHEN** the user opens a quest
- **THEN** each objective is listed with its type, description, required count, and map or target when the dataset provides them

#### Scenario: Rewards and unlocks

- **WHEN** a quest grants items, trader loyalty, experience, or unlocks further quests
- **THEN** each reward and unlock is listed with a link to the affected item, trader, or quest where applicable

### Requirement: Progress recording

The active profile SHALL record a progress state for each quest, and state changes SHALL be persisted
immediately and reflected everywhere the quest appears.

#### Scenario: Mark quest complete

- **WHEN** the user marks a quest as completed
- **THEN** the state is saved locally, the quest shows as completed in the catalog, and dependent quest availability is recomputed

#### Scenario: Undo completion

- **WHEN** the user reverts a completed quest
- **THEN** the quest returns to its previous state and quests that depended on it become locked again

### Requirement: Objective-level tracking

For quests with countable objectives, the tracker SHALL allow recording partial progress per objective and
SHALL derive quest completion only when every required objective is satisfied.

#### Scenario: Partial objective progress

- **WHEN** a quest requires 5 kills and the user records 3
- **THEN** the quest remains in progress and shows 3 of 5 for that objective

#### Scenario: Manual quest completion override

- **WHEN** the user marks a quest complete while objectives remain unsatisfied
- **THEN** the app asks for confirmation and, if confirmed, records the quest as complete without altering the recorded objective counts

### Requirement: Progress survives data updates

Quest progress SHALL be keyed by stable quest and objective identifiers and SHALL NOT be lost or
misattributed when the dataset is updated.

#### Scenario: Quest text changes upstream

- **WHEN** an updated dataset changes a quest's name or objective descriptions but keeps its identifiers
- **THEN** the profile's recorded progress still applies to that quest

#### Scenario: Quest removed upstream

- **WHEN** a quest present in the profile no longer exists in the active dataset
- **THEN** the tracker lists it separately as unavailable, preserves its recorded state, and excludes it from requirement calculations that need current data

### Requirement: Progress is scoped to the active profile

Quest and objective progress SHALL be read from and written to the active profile only, and switching
profiles SHALL immediately change every derived quest state.

#### Scenario: Switch game mode

- **WHEN** the user switches from the PvP profile to the PvE profile
- **THEN** quest states reflect the PvE profile's own progress and the PvP progress is unchanged

### Requirement: Next-step guidance

The tracker SHALL offer a view of quests the active profile can start now, ordered by a user-selectable
criterion such as trader, level, or map, without requiring the user to open each quest.

#### Scenario: Available quests view

- **WHEN** the user opens the available-quests view
- **THEN** only unstarted quests whose requirements are satisfied are listed, with trader, level, and map shown per quest

#### Scenario: Everything available is done

- **WHEN** no quest is currently available
- **THEN** the view explains why, for example that remaining quests are locked by level or by an incomplete prerequisite

### Requirement: Quest data reflects the selected game mode

The tracker SHALL use the quest dataset belonging to the active profile's game mode and SHALL NOT blend
quests from different modes in one view.

#### Scenario: PvE-only quest

- **WHEN** a quest exists in the PvE dataset but not in the regular dataset and the active profile is regular
- **THEN** that quest does not appear in the regular profile's catalog
