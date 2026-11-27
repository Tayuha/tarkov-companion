# Phosphor design system

The client uses a single visual direction: **phosphor green**. It is a dense,
quiet, local-first interface built from green-black surfaces, pale-green text and
a mint accent reserved for decisions and confirmed progress. The full visual
reference is [`design/README.md`](../design/README.md) and the previews in
`design/preview/`.

This document covers the shared Flutter layer added in T8.12. It is token,
theme and primitive code plus the component gallery. T8.13 installed
`buildAppTheme()` in `app/lib/main.dart` and migrated the Items catalog and
item detail; Quests still migrate in T8.14. The component gallery and the theme
tests remain the proof of the system.

## Where it lives

| File | Purpose |
|---|---|
| `app/packages/features/lib/src/theme/app_tokens.dart` | `AppTokens` — the only file with colour literals. |
| `app/packages/features/lib/src/theme/app_theme.dart` | `buildAppTheme()` — dark `ThemeData`, `ColorScheme`, typography and component themes. |
| `app/packages/features/lib/src/theme/app_primitives.dart` | Panels, labels, buttons, chips, status badges, stat tiles, progress bars and the sample data row. |
| `app/packages/features/lib/src/theme/theme.dart` | Barrel export, re-exported from `tarkov_companion_features.dart`. |
| `app/packages/features/test/theme/` | Contrast, theme and primitive tests plus the 1x component golden. |

## Colour tokens

| Token | Hex | Use |
|---|---|---|
| `background` | `#070D08` | Page and table background |
| `surface` | `#0D1510` | Cards and panels |
| `surfaceRaised` | `#121C15` | Inputs and raised cells |
| `surfaceHigh` | `#18251B` | Highest resting surface |
| `border` | `#223529` | Structural rules and outlines |
| `borderSoft` | `#1B2A20` | Quiet separators |
| `text` | `#DCF3E2` | Primary text |
| `muted` | `#8FA894` | Secondary text and labels |
| `dim` | `#5F7A66` | Disabled and decorative text |
| `accent` | `#7DF7A8` | Decision, selection, confirmed progress |
| `accentDeep` | `#17452A` | Selected fill behind the accent |
| `success` | `#5FBF7A` | Available and successful states |
| `danger` | `#D27A6A` | Failed states and negative change |
| `info` | `#7DDCC4` | In-progress states and links |
| `value` | `#C9D99A` | Prices, standing, numeric values |
| `onAccent` | `#04140A` | Text drawn on the accent fill |

Contrast, measured with the WCAG 2.x relative-luminance formula:

| Pair | Ratio |
|---|---|
| `text` / `surface` | 15.87 |
| `text` / `background` | 16.78 |
| `accent` / `background` | 14.71 |
| `onAccent` / `accent` | 14.19 |
| `muted` / `surface` | 7.24 |
| `success` / `surface` | 8.15 |
| `danger` / `surface` | 5.95 |
| `info` / `surface` | 11.40 |
| `value` / `surface` | 12.26 |

`dim` is 3.94 on `surface` and is intentionally limited to disabled or
non-essential text; it is not a body-text colour.

## Scales

**Spacing** — a strict 4 px grid: `4, 8, 12, 16, 24, 32, 48`
(`spaceXs` … `space3xl`).

**Radii** — `2` structural corners, `4` controls, and `999` for pills.

**Type** — Fira Sans Condensed for UI, DejaVu Sans Mono for data.

| Token | Size | Family | Weight |
|---|---|---|---|
| `display` | 34 | Fira Sans Condensed | 700 |
| `h1` | 22 | Fira Sans Condensed | 600 |
| `h2` | 16 | Fira Sans Condensed | 600 |
| `body` | 12 | Fira Sans Condensed | 400 |
| `label` | 8 | DejaVu Sans Mono | 500, 1.2 tracking, uppercase |
| `data` | 11 | DejaVu Sans Mono | 400 |

Numbers keep their sign or currency. Colour is never the only carrier of
meaning.

## Using the theme

Import the features barrel:

```dart
import 'package:tarkov_companion_features/tarkov_companion_features.dart';
```

Read the active tokens, or build the shared theme:

```dart
final tokens = AppTokens.of(context);
final theme = buildAppTheme();
```

`buildAppTheme()` returns the theme; the app installs it in `app/lib/main.dart`.
Tests and isolated screen previews opt in explicitly:

```dart
MaterialApp(
  theme: buildAppTheme(),
  home: const CatalogScreen(...),
);
```

Token access inside a primitive:

```dart
Container(
  padding: EdgeInsets.all(tokens.spaceLg),
  decoration: BoxDecoration(
    color: tokens.surface,
    border: Border.all(color: tokens.border),
    borderRadius: BorderRadius.circular(tokens.radiusSm),
  ),
);
```

Never write a colour literal outside `app_tokens.dart`. Derive hover, tint and
disabled colours from a token with `withValues(alpha: …)` or `Color.alphaBlend`.

## Primitives

| Widget | Use |
|---|---|
| `AppPanel` | A flat bordered surface with an optional uppercase label and trailing widget. |
| `AppSectionLabel` | An 8 px uppercase mono section or field label. |
| `AppButton` | Compact action with `primary`, `secondary`, `ghost` and `danger` variants. |
| `AppChip` | A pill filter chip, `selected` or neutral. |
| `AppStatusBadge` | `available`, `inProgress`, `completed`, `failed` and `locked` states. |
| `AppStatTile` | A label/value cell for inspector statistics. |
| `AppProgressBar` | A 3 px progress rail with optional label and readout. |
| `AppDataRow` | The compact name/meta/value/delta row used as the list density sample. |

### Buttons

```dart
AppButton(
  label: 'Mark completed',
  variant: AppButtonVariant.secondary,
  onPressed: markCompleted,
);

AppButton(
  label: 'Mark in progress',
  onPressed: markInProgress,
);

AppButton(label: 'Delete', variant: AppButtonVariant.danger, onPressed: delete);
```

A null `onPressed` renders the disabled treatment. Use `expand: true` when the
button should fill the parent width.

### Chips and states

```dart
const AppChip(label: 'Flea eligible', selected: true);
const AppChip(label: 'Neutral');
const AppStatusBadge(status: AppStatus.inProgress);
```

### Panel, statistics and progress

```dart
AppPanel(
  label: 'Objective progress',
  trailing: Text('2 / 3', style: tokens.dataStyle),
  child: AppProgressBar(
    value: 2 / 3,
    label: 'Find the convoy',
    trailing: '2 / 3',
  ),
);

const AppStatTile(label: 'Recoil', value: '63 / 171');
```

### Sample data row

```dart
AppDataRow(
  name: 'Colt M4A1 5.56x45',
  meta: 'Assault rifle · 5.56x45',
  value: '114,728 ₽',
  delta: '+22.0%',
  deltaColor: tokens.success,
  selected: true,
);
```

The row is presentational. Screens wrap it in an `InkWell` or selection
handler when they migrate.

## Fonts and licences

The app bundles five faces under `app/assets/fonts/`:

| File | Family | Weight |
|---|---|---|
| `FiraSansCondensed-Regular.ttf` | Fira Sans Condensed | 400 |
| `FiraSansCondensed-SemiBold.ttf` | Fira Sans Condensed | 600 |
| `FiraSansCondensed-Bold.ttf` | Fira Sans Condensed | 700 |
| `DejaVuSansMono.ttf` | DejaVu Sans Mono | 400 |
| `DejaVuSansMono-Bold.ttf` | DejaVu Sans Mono | 700 |

They are declared in `app/pubspec.yaml`. Licences ship beside the binaries:

- `app/assets/licenses/FiraSans-OFL.txt` — SIL Open Font License 1.1, from
  `/usr/share/licenses/ttf-fira-sans/OFL.txt`.
- `app/assets/licenses/DejaVu-LICENSE.txt` — Bitstream Vera / DejaVu licence,
  from `/usr/share/licenses/ttf-dejavu/LICENSE`.

Both licences are declared as app assets. Font files themselves are build
inputs and are not exposed as runtime assets.

## Tests and the golden

```bash
cd app
flutter test packages/features/test/theme
flutter test packages/features/test/theme --update-goldens
```

- `tokens_test.dart` checks the required WCAG AA pairs, the spacing/radius/type
  scales, `copyWith` and `lerp`.
- `theme_test.dart` checks the dark `ColorScheme`, the token extension, both
  font families, and that Material's default primary is gone.
- `primitives_test.dart` smoke-tests every primitive and compares a **1x,
  880 × 660** component gallery on the phosphor background. The test loads the
  bundled fonts directly so the golden shows real type rather than Ahem boxes.

Regenerate the golden only on Linux and inspect the PNG before committing. The
gallery is intentionally small and flat so it remains stable across runs.

## Rules

- Density is the feature. Desktop rows stay near 72 px; touch rows near 84–86 px.
- Accent means a decision, a selection or confirmed progress. It is not
  decoration.
- No rounded glass, gloss or decorative gradients. Two-pixel corners at most.
- Every screen must stay legible offline and at 100% zoom.
- Item art remains a placeholder until licensing/branding is decided.
- Items migrated in T8.13; Quests migrate in T8.14.
