/// Bundle ingestion, local database, and repositories.
///
/// This package is pure Dart: it may import `tarkov_companion_core`, but not
/// Flutter, `dart:ui`, or `tarkov_companion_features`.
/// The rule is enforced by `app/tool/check_architecture.dart`.
library;

export 'src/bundle/bundle_contract.dart';
export 'src/bundle/canonical_json.dart';
export 'src/bundle/game_mode.dart';
export 'src/bundle/manifest.dart';
export 'src/catalog/catalog_query.dart';
export 'src/catalog/catalog_repository.dart';
export 'src/catalog/item_detail.dart';
export 'src/catalog/items_repository.dart';
export 'src/catalog/price_freshness.dart';
export 'src/database/app_database.dart';
export 'src/database/connection.dart';
export 'src/database/dataset_state_repository.dart';
export 'src/database/fts.dart';
export 'src/database/migration_runner.dart';
export 'src/database/tables.dart' hide AppSettings;
export 'src/dataset_kind.dart';
export 'src/logging/log_export.dart';
export 'src/logging/log_level.dart';
export 'src/logging/log_record.dart';
export 'src/logging/log_sink.dart';
export 'src/logging/logger.dart';
export 'src/logging/rotating_file_log_sink.dart';
export 'src/net/allowlisted_http_client.dart';
export 'src/net/host_allowlist.dart';
export 'src/net/http_errors.dart';
export 'src/profiles/profile_repository.dart';
export 'src/quests/quest_availability.dart';
export 'src/quests/quest_detail.dart';
export 'src/quests/quest_query.dart';
export 'src/quests/quest_repository.dart';
export 'src/settings/app_settings.dart';
export 'src/settings/settings_repository.dart';
export 'src/sync/dataset_downloader.dart';
export 'src/sync/dataset_ingestor.dart';
export 'src/sync/jsonl_reader.dart';
export 'src/sync/manifest_fetcher.dart';
export 'src/sync/manifest_repository.dart';
export 'src/sync/scheduler.dart';
export 'src/sync/sync_coordinator.dart';
