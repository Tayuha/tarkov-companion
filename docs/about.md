# About screen

The About screen (`AboutScreen` in
`app/packages/features/lib/src/about/about_screen.dart`) is reached from the
footer below the navigation shell, not from a fourth primary destination. It
shows:

| Field | Source |
|---|---|
| Application version | The build version passed by `HomeShell` (`0.1.0` today). |
| Bundle / manifest version | `DataBundleStatus.manifestVersion` and `bundleSchemaVersion`, parsed from the cached manifest. |
| Bundle generated time | `manifest.generatedAt`, the upstream build timestamp. |
| Last checked | `remoteManifest.lastCheckedAt` for the active mode. |
| Datasets applied | `datasetState` row count versus the seven datasets in a complete bundle. |
| Dataset age | Now minus the oldest applied `datasetState.appliedAt`. |
| Licence | MIT, with the standard permission and warranty text. |
| Attribution | tarkov.dev data, the Escape from Tarkov trademark notice, and the no-bundled-game-art statement. |

`DataBundleStatus.read` in
`app/packages/data/lib/src/sync/data_bundle_status.dart` assembles the value
from `DatasetStateRepository`, `ManifestRepository` and the cached manifest
body. It is local-only and performs no request. A corrupt cached manifest loses
only the manifest-version rows; the applied-dataset summary is still shown.

## Attribution text

The screen states that:

* game data is provided by [tarkov.dev](https://tarkov.dev) and used under that
  project's terms;
* Escape from Tarkov is a registered trademark of Battlestate Games Limited,
  and this is an unofficial fan-made companion with no affiliation or
  endorsement;
* no game art or other game assets are bundled — item images are fetched from
  the tarkov.dev CDN at runtime and remain their owners' property.

These statements match `NOTICE` and the data-bundle contract in
[`data-bundles.md`](data-bundles.md).

## Test

`app/packages/features/test/about/about_screen_test.dart` checks the rendered
values for a complete bundle and for a session with no applied data, then
compares a golden at 900×1400 with the bundled Fira Sans Condensed and DejaVu
Sans Mono fonts and Material Icons loaded by
`test/theme/support/load_fonts.dart`.
