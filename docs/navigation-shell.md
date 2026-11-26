# Navigation shell

`HomeShell` (`app/lib/src/home_shell.dart`) is the landing interface once the
local dataset is complete. `AppRoot` shows the first-run gate first and then
hands the opened session's repositories to the shell, so the shell never opens
the database itself.

## Layout rules

| Window width | Navigation | Body |
| --- | --- | --- |
| 700 logical pixels or wider | Persistent left `NavigationRail` | Tabs side by side in an `IndexedStack` |
| Narrower than 700 | Bottom `NavigationBar` | The same `IndexedStack`, full width |

The threshold lives in one place, `_HomeShellState._railBreakpoint`. The wide
layout is the Linux desktop target; the bottom bar is the shell's mobile
layout, already in place for the Android release. The app bar title follows the
selected tab ("Items" or "Quests"), and the selected destination is highlighted
by the Material navigation widgets.

## Tabs and routing

* **Items** renders `CatalogScreen` with the session's `CatalogRepository`.
  Tapping a row pushes `ItemDetailScreen` with a standard `MaterialPageRoute`.
* **Quests** renders `QuestListScreen` with the session's `QuestRepository` and
  the active profile id. Tapping a quest calls the shell's `onQuestSelected`
  callback; the quest detail route is the next task, so the shell deliberately
  does not push anything yet.

Back, the app bar back button and Escape all leave a pushed page through the
standard `Navigator`. Escape is wired once in `TarkovCompanionApp`; when the root
route cannot be popped the action is disabled, so the default Flutter dismissal
handling still closes menus and text toolbars.

## State preservation

Both tabs are children of one `IndexedStack` and stay mounted when hidden.
Switching tabs therefore preserves:

* catalog and quest search text, including a pending debounce;
* active filter chips and sort order;
* scroll position and any additional pages loaded with **Load more**.

The trade-off is that both repositories run their first query as soon as the
shell builds, even for the hidden tab. Against the local SQLite database this
is negligible, and it is what makes a tab switch instant instead of rebuilding
the screen and losing its state. Do not replace the `IndexedStack` with a
conditional `body` without moving the state into a controller first.

## Adding a tab

Add a value to `_HomeTab`, a matching destination to the rail and the bottom
bar, and one child to the `IndexedStack`. Keep the child order aligned with
`_HomeTab.values`; the selected index is stored as the enum, not as a raw int.
