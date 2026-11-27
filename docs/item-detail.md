# Item detail view

The item detail view is the read-only page for one catalog item. It is built
from the local database only and makes no network request.

## Data API

`CatalogRepository.itemDetail(id)` returns an `ItemDetail` or `null` when the
current dataset has no item with that id. It reads:

- the indexed `items` columns (`name`, `shortName`, `weight`, `width`,
  `height`);
- the canonical `payload` JSON for everything else (`description`,
  `stackMaxSize`, links, conflicts, type-specific `properties`);
- the `itemTypes` and `itemCategories` join rows;
- the display names of categories from the `gameRecords` records of kind
  `itemCategory` and `handbookCategory`, falling back to the category id when a
  name is absent.

The payload is parsed once into a typed `ItemProperties` subclass:

| `propertiesType` / item type | Model | Fields |
|---|---|---|
| `ItemPropertiesWeapon` / `gun` | `WeaponProperties` | caliber, fire rate, ergonomics, vertical and horizontal recoil, effective range, fire modes, attachment slots |
| `ItemPropertiesAmmo` | `AmmunitionProperties` | caliber, damage, penetration power, armor damage |
| `ItemPropertiesArmor`/`Helmet`, `armor`/`helmet` | `ArmorProperties` | class, durability, protected zones, material |
| `ItemPropertiesMedKit`/`Stim`/`MedicalItem`/`Painkiller`/`SurgicalKit`, `meds`/`injectors` | `MedicalProperties` | uses, hit points, hit points per use, use time, cures, stim effects |
| anything else | `GenericProperties` | no type-specific fields |

A corrupt payload throws a `FormatException`; the screen shows its error state
instead of inventing values. An unknown id returns `null`, which the screen
renders as the not-found state.

## Sections

1. **Header** — placeholder icon, name, short name, and type chips.
2. **Properties** — weight, grid size, and stack limit when the bundle has
   them.
3. **Categories** — item and handbook category labels, when the item has any.
4. **Links** — the wiki URL and the tarkov.dev page as selectable text. The
   app does not open an external browser yet.
5. **Type-specific section** — exactly one of *Weapon*, *Ammunition*, *Armor*
   or *Medical*, depending on the typed property set. A weapon adds its
   compatible slots with required/optional markers.
6. **Description** — the localized description, when present.

## Omission rule

A property is rendered only when it applies to the item's kind **and** has a
value. The rule has two layers:

- **Type layer.** The property groups are disjoint classes, so a weapon has no
  `damage` field to render and ammunition has no `ergonomics` field. A section
  whose item kind does not match is never created.
- **Value layer.** Every row is added only when its parsed value is non-null and
  non-empty (positive numbers, non-empty strings and lists). No row is ever
  rendered as zero or "N/A", and a typed section with no rows is omitted
  entirely.

A barter-only item (for example the Leatherman Multitool) therefore shows the
header, base properties, categories, links, and description — and no
type-specific section.

Zero is treated as "no value" for the type-specific numeric fields because the
bundle uses absent fields for "not applicable"; a legitimate zero (such as a
modifier or penalty) is not part of the sections rendered here.

## Out of scope

Acquisition and disposition (task 5.4), price presentation (5.5), the image cache
(5.6), price history (5.7), and deep-link routing (5.8) are separate tasks. The
image slot is a neutral placeholder and prices are not shown on this screen.

## Tests

`app/packages/features/test/catalog/item_detail_screen_test.dart` renders a
weapon, ammunition, armor, and a barter-only item as golden images under
`goldens/` (960 × 1500, the phosphor theme and bundled fonts, device pixel
ratio 1). It also asserts the omission rule structurally: a weapon has no
ammunition rows, an ammunition item has no weapon rows, a barter-only item has
no typed section, and a medkit without `uses` does not show a Uses row. The
single-column and wide two-column layouts are covered, as are loading,
not-found with back navigation, and corrupt-payload error states.

`app/packages/data/test/catalog/item_detail_test.dart` checks the parser against
the committed normalized item fixture, including a missing id and a corrupt
payload.
