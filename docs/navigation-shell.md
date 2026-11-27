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
selected tab ("Items", "Quests" or "Profiles"), and the selected destination is
highlighted by the Material navigation widgets.

A third **Profiles** destination appears only when `HomeShell.profileServices`
is supplied. Without it (shell tests, recovery, a session built without SQLite)
the shell keeps exactly the original two tabs.

## Tabs and routing

* **Items** renders `CatalogScreen` with the session's `CatalogRepository`.
  Tapping a row pushes `ItemDetailScreen` with a standard `MaterialPageRoute`.
* **Quests** renders `QuestListScreen` with the session's `QuestRepository` and
  the active profile id. Tapping a quest pushes `QuestDetailScreen` (the
  `onQuestSelected` callback is the test seam).
* **Profiles** renders `ProfilesScreen` with the session's `ProfileServices`.
  Editing a level, switching, resetting, deleting or importing calls
  `onProfileChanged`, which updates the shell's active id and bumps a revision
  key on the Quests tab so the mounted list re-derives availability.
  Deleting the last profile reports `null`; the quest tab then reads with no
  profile until one is created.

Back, the app bar back button and Escape all leave a pushed page through the
standard `Navigator`. Escape is wired once in `TarkovCompanionApp`; when the root
route cannot be popped the action is disabled, so the default Flutter dismissal
handling still closes menus and text toolbars.

## Deep links

`AppRoot` accepts a `DeepLinkInbox`; a launch argument
(`--item-id=<id>`) and a second process both queue an item id there. Once the
session is ready, the shell pushes `ItemDetailScreen` over `HomeShell`, so the
catalog stays mounted underneath and the removed-item state returns to it with
the normal back action. The launch and second-instance contracts are documented
in [`deep-links.md`](deep-links.md); window geometry and single-instance
behavior are in [`window.md`](window.md).

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

Add a value to `_HomeTab`, add it to `_tabs` (conditionally if it needs
services), a matching destination to the rail and the bottom bar, and one child
to the `IndexedStack`. Keep the child order aligned with `_tabs`; the selected
index is `_tabs.indexOf(_tab)`, not a raw enum index, so optional tabs do not
shift the others.
