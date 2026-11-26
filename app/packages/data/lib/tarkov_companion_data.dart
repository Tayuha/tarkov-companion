/// Bundle ingestion, local database, and repositories.
///
/// This package is pure Dart: it may import `tarkov_companion_core`, but not
/// Flutter, `dart:ui`, or `tarkov_companion_features`.
/// The rule is enforced by `app/tool/check_architecture.dart`.
library;

export 'src/dataset_kind.dart';
