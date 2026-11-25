# Spec Delta

## Purpose

Gives players a fast, searchable reference for every in-game item, including its combat and economic
properties, where it can be obtained, and what it is currently worth.

## ADDED Requirements

### Requirement: Item search

The catalog SHALL provide full-text search over item name, short name, and normalized name, returning
results as the user types without requiring a network request.

#### Scenario: Search by common name

- **WHEN** the user types "m4a1"
- **THEN** the Colt M4A1 and other matching items appear, ordered by relevance, before the user presses Enter

#### Scenario: Accent-insensitive match

- **WHEN** the user types a query without diacritics that matches an item name containing diacritics
- **THEN** the item is included in the results

#### Scenario: No matches

- **WHEN** the query matches no item
- **THEN** the catalog shows an explicit empty state with the query preserved and no error

### Requirement: Item filtering and sorting

The catalog SHALL support filtering by category, item type, and flea-market eligibility, and SHALL support
sorting by name, base price, flea price, and weight. Active filters SHALL be visible and individually
removable.

#### Scenario: Combined filters

- **WHEN** the user filters to ammunition that is flea-eligible and sorts by price ascending
- **THEN** only matching items are listed, in ascending price order, with all active filters shown

#### Scenario: Zero-result filter set

- **WHEN** the active filter combination matches nothing
- **THEN** the catalog shows which filters are active and offers a one-action reset

### Requirement: Item detail

Selecting an item SHALL show a detail view containing its image, name, short name, description, weight,
grid size, stack limit, categories, applicable properties for its type (such as damage, penetration, armor
class, or ergonomics), and its wiki link.

#### Scenario: Weapon detail

- **WHEN** the user opens a weapon
- **THEN** the detail view shows its caliber, fire rate, ergonomics, recoil, effective range, and compatible slot summary alongside its ordinary properties

#### Scenario: Property not applicable

- **WHEN** an item has no value for a property that applies to other items of a different type
- **THEN** that property is omitted rather than rendered as zero or "N/A"

### Requirement: Acquisition and disposition sources

The item detail SHALL list the ways the item can be obtained and disposed of that the dataset provides:
trader purchases and sales with prices and loyalty levels, flea-market eligibility and minimum level,
barter offers, crafts that produce it, and quests that require or reward it.

#### Scenario: Item is a quest requirement

- **WHEN** the user opens an item required by one or more quests
- **THEN** those quests are listed with a link to each quest detail

#### Scenario: Item cannot be sold on the flea market

- **WHEN** an item is banned from the flea market
- **THEN** the detail view states that clearly instead of showing a flea price

### Requirement: Price presentation

The item detail SHALL display the latest flea price, 24-hour average, 48-hour change, best trader sell
price, and the timestamp of the observations, and SHALL distinguish a missing price from a price of zero.

#### Scenario: Complete price data

- **WHEN** an item has flea and trader prices
- **THEN** the view shows each value with its source, the observation time, and the direction of the 48-hour change

#### Scenario: Missing flea price

- **WHEN** an item has trader prices but no flea observation
- **THEN** the flea fields show an explicit "no recent data" state and trader prices remain visible

### Requirement: Price history

The item detail SHALL provide a price history view covering the available observation period, with
minimum and average price series, and SHALL function from cached history when offline.

#### Scenario: History loaded on demand

- **WHEN** the user opens the price history for an item
- **THEN** the app loads the history for that item, caches it, and renders a chart with a readable time axis

#### Scenario: History unavailable offline

- **WHEN** the user opens price history for an item with no cached history and no connection
- **THEN** the app states that history needs a connection, while keeping the current price fields visible

### Requirement: Item images work offline and degrade gracefully

Item images SHALL be cached locally after first display and SHALL fall back to a neutral placeholder when
an image is unavailable, without blocking or breaking layout.

#### Scenario: Image already cached

- **WHEN** the user reopens an item whose image was displayed before, with no connection
- **THEN** the cached image is shown

#### Scenario: Broken image link

- **WHEN** an image request fails or returns an unsupported format
- **THEN** the placeholder is shown at the correct aspect ratio and the rest of the detail view remains usable

### Requirement: Stable item identity

Every item SHALL be addressable by its game item identifier, and any in-app link, deep link, or saved
reference SHALL resolve to the same item across data updates.

#### Scenario: Deep link after data update

- **WHEN** the user opens a link to an item and the dataset has since been updated
- **THEN** the item resolves by identifier and displays the current data

#### Scenario: Item removed upstream

- **WHEN** a referenced item identifier no longer exists in the current dataset
- **THEN** the app shows a clear "item no longer available" state and a path back to search

### Requirement: Large result sets stay responsive

The catalog SHALL remain interactive with the complete item set loaded, using incremental rendering and
without loading all images or history eagerly.

#### Scenario: Scrolling the full catalog

- **WHEN** the user scrolls rapidly through an unfiltered item list
- **THEN** rows render incrementally and input latency stays within the app's interaction budget
