import '../database/app_database.dart';
import 'profile_repository.dart';
import 'progress_export.dart';
import 'progress_import.dart';

/// The profile-facing data services, built over one database.
///
/// The app shell exposes this single object instead of separately wiring the
/// repository, writer and importer, so the profile screen cannot be given a
/// writer over a different database than the repository it lists.
final class ProfileServices {
  ProfileServices(
    AppDatabase database, {
    DateTime Function()? clock,
    String Function()? idGenerator,
    void Function()? beforeImportCommit,
  }) : profiles = ProfileRepository(
         database,
         clock: clock,
         idGenerator: idGenerator,
       ),
       exporter = ProgressExportWriter(database, clock: clock),
       importer = ProgressImporter(
         database,
         clock: clock,
         idGenerator: idGenerator,
         beforeCommit: beforeImportCommit,
       );

  final ProfileRepository profiles;
  final ProgressExportWriter exporter;
  final ProgressImporter importer;
}
