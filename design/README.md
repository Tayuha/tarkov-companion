# Tarkov Companion — visual concept

A first FigCraft pass for the desktop and mobile app, built from two references:

- **[Database for Tarkov](https://db4tarkov.com/quest)** — dense quest rows, trader strip, orange active
  state, immediate numeric comparison, almost no decorative chrome.
- **[Tarkov Tracker](https://tarkovtracker.io/)** — olive/brown surfaces, bone text, monospace stats,
  green "confirmed progress" language, quiet panels.

This is an independent fan project. No game artwork is bundled; item images are neutral placeholders.

## Files

| File | What it is |
|---|---|
| `tarkov-companion.figcraft` | Editable FigCraft document, five pages (original) |
| `tarkov-companion-night-vision.figcraft` | Separate copy with the Items palette remapped to phosphor green |
| `preview/00-tokens.png` | Palette, type scale, components |
| `preview/01-items.png` | Desktop Items — dense catalog + inspector |
| `preview/02-quests.png` | Desktop Quests — trader strip, list, detail |
| `preview/03-mobile-items.png` | Mobile Items |
| `preview/04-mobile-quests.png` | Mobile Quests |
| `preview/05-items-night-vision.png` | Items in the chosen phosphor variant |
| `preview/06-items-1920-nv.png` | Phosphor Items at 1920×1080 |
| `preview/index.html` | Gallery of the five previews |

## Pages

1. **00 · Tokens & Type** — palette, semantic colours, type scale, buttons, chips, progress, sample row.
2. **01 · Desktop · Items** — 1440×900. Left rail, mode switch, dense table, selected row, item inspector
   with stats, trader offers, price sparkline.
3. **02 · Desktop · Quests** — 1440×900. Trader portrait strip, task list with state/progress, quest detail
   with objectives, requirements, rewards, notes and status actions.
4. **03 · Mobile · Items** — 390×844. Compact list with per-item price and change; bottom navigation.
5. **04 · Mobile · Quests** — 390×844. Trader initials, availability tabs, compact task rows.
6. **05 · Items · Night Vision** — separate file. The same Items screen with the palette shifted to
   phosphor green; the original document is untouched.
7. **05 · Wide · Items 1920** — 1920×1080 in the phosphor file. Extra width buys two columns
   (Buy Limit, Updated) and a 506 px inspector; 11 rows fit without scrolling.

## Items refinement (option 1)

The desktop Items screen is now grounded in the running app:

- **Column priorities at 1440 px:** Item, Flea price + Base subline, 24 h change, Best trader, Weight,
  Slots. Base price never takes a second primary column; it is a muted subline under the flea low.
- **Responsive fallback:** at 1280 px drop Slots; at 1024 px drop Weight and move best-trader detail into
  the inspector. Keep item, flea price, 24 h and the trader summary.
- **Spacing:** 8 px grid; 72 px table rows; 34 px header; 52 px filter bar; 16 px inspector padding; the
  inspector action sits inside the 784 px panel instead of clipping at the window edge.
- **Footer:** dataset age, offline-copy state and the active sort, so the table never floats without
  context.
- **States:** one selected row (orange bar + tinted fill), alternating row surfaces, stale/— values in
  muted grey, positive/negative deltas in green/red.

## Chosen direction — phosphor green

**Decision: the phosphor-green variant is the chosen direction.** The orange file remains as the alternative
and is not the implementation target.

`tarkov-companion-night-vision.figcraft` is a **separate copy** generated from the refined document, now with
its own 1920×1080 Items page. It is not a second theme inside the original file.

- Backgrounds shift to green-black (`#070D08` base), surfaces to `#0D1510` / `#121C15`.
- The decision orange `#E08A3C` becomes phosphor mint `#7DF7A8`; the deep selected fill becomes
  `#17452A`.
- Success, info and danger stay distinguishable (`#5FBF7A`, `#7DDCC4`, `#D27A6A`); bone text becomes
  pale green `#DCF3E2`.
- The header records `NIGHT VISION VARIANT · PHOSPHOR GREEN`, so the copy cannot be mistaken for the
  original.

## Resolution behaviour

The layout is adaptive, not scaled:

| Width | Behaviour |
|---|---|
| 1024–1279 | Compact: hide Slots and Weight, keep Item/Flea/24h/Trader; inspector narrows. |
| 1280–1439 | Standard: hide Slots; keep Weight and trader summary. |
| 1440–1919 | Full: the six-column Items page in this document. |
| 1920+ | Wide (second monitor): add Buy Limit and Updated, 1330 px table + 506 px inspector. |
| ≥ 2560 | Cap the content width; do not stretch the table further. |

The 1920 page is the reference for the second-monitor case. It is not a 1.33× scale of the 1440 page: it
adds data columns and increases the Inspector rather than enlarging every row.

## Design tokens

### Colour

| Token | Hex | Use |
|---|---|---|
| Void | `#0C0E0C` | Page and table background |
| Surface | `#141714` | Cards, panels |
| Surface 2 | `#1A1E1A` | Inputs, icon wells |
| Surface 3 | `#20251F` | Raised segments |
| Border | `#2C332C` | Structural rules |
| Bone | `#E8E2CF` | Primary text |
| Muted | `#8F9385` | Secondary text |
| Orange | `#E08A3C` | Active row, decision, primary action |
| Orange deep | `#7A4318` | Selected fill |
| Green | `#6FA96F` | Confirmed progress, available |
| Red | `#C05A4A` | Failed, negative change |
| Cyan | `#6FB7C4` | In progress, links |
| Gold | `#C9A35C` | Value, trader standing |

### Type

- **UI/display:** Fira Sans Condensed (Bold, SemiBold, Regular).
- **Data:** DejaVu Sans Mono (prices, levels, counts, deltas, labels).
- Labels are 7–9 px mono, uppercase, ~1.2 tracking.
- Numbers always carry their sign or currency; never colour alone.

### Rules

- Density is the feature: 72 px desktop rows, 84–86 px touch rows.
- Orange is a decision or an active selection; green is confirmed progress.
- No rounded glass, no gloss, no decorative gradients. 2 px corners at most.
- Every screen must remain legible offline and at 100% zoom.
- Item art is a placeholder until licensing/branding is decided.

## Editing

The FigCraft Flatpak cannot see the repo directly. Use the round-trip helper:

```bash
figcraft-stage in design/tarkov-companion.figcraft
# open the staged path in FigCraft, edit, save
figcraft-stage out design/tarkov-companion.figcraft
```

Preview PNGs were exported at 1× from the same document. Re-export after edits if the concept changes.

## Status

Concept only. The running Linux app uses plain Material widgets; this document is the visual target for the
design pass, not an implementation.
