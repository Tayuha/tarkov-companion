# Item deep links

Every item is addressable by its game item identifier (the Tarkov id such as
`5447a9cd4bdc2dbd208b4567`). The desktop shell accepts that id at launch and
opens the item detail through the normal catalog route.

## Launch forms

The runner passes its arguments to the Flutter entrypoint, so all of these work:

```sh
tarkov_companion --item-id=5447a9cd4bdc2dbd208b4567
tarkov_companion --item-id 5447a9cd4bdc2dbd208b4567
tarkov_companion 'tarkov-companion://item/5447a9cd4bdc2dbd208b4567'
```

`--item-id=<id>` is the canonical form; the separated form and the URI scheme
exist for desktop launchers and future `xdg-open` handlers. URI path segments
are percent-decoded. Unknown arguments are ignored and the first well-formed
item request wins.

Parsing lives in `LaunchRequest` (`app/lib/src/launch_request.dart`) and is
covered by `app/test/launch_request_test.dart`.

## Resolution and fallback

The id is resolved with `CatalogRepository.itemDetail` against the currently
applied dataset:

- **Known id** — `ItemDetailScreen` opens with the current data, even when the
  dataset has been refreshed since the link was saved.
- **Removed or unknown id** — the screen shows the explicit
  "Item no longer available" state and a **Back to catalog** button. The button
  pops the detail route, leaving the catalog visible.
- **No applied dataset** — a link arriving before data exists waits for the
  first-run sync to finish, then opens the detail.

Deep links are queued in `DeepLinkInbox` (`app/lib/src/deep_links.dart`).
`AppRoot` drains the queue on the next frame after the session is ready, so a
launch link cannot race the database opening.

## Second launch

A launch while the app is running does not open a second database. The key
process forwards `{"type":"focus","itemId":"<id>"}` over
`$XDG_RUNTIME_DIR/tarkov_companion/instance.sock`, focuses the existing
window, and exits. The primary process adds the id to the same inbox, so

```sh
tarkov_companion --item-id=5447a9cd4bdc2dbd208b4567
```

opens the item in the window that is already running.

See [`window.md`](window.md) for the single-instance lock and the manual
two-launch check.

## Tests

- `app/test/launch_request_test.dart` — all accepted forms and malformed input.
- `app/test/deep_links_test.dart` — known id opens the fixture item, unknown id
  shows the removed state and returns to the catalog, and a link queued after
  startup opens the detail once.
