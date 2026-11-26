import 'package:material_ui/material_ui.dart';

import 'src/app_paths.dart';
import 'src/app_root.dart';
import 'src/app_session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    TarkovCompanionApp(
      openSession: () => openAppSession(paths: AppPaths.resolve()),
    ),
  );
}

/// The desktop shell.
///
/// The app does not open the network here. [AppRoot] opens the local database,
/// then either shows the first-run data gate or the last applied dataset. The
/// session opener is a parameter so widget tests can substitute a fake.
class TarkovCompanionApp extends StatelessWidget {
  const TarkovCompanionApp({super.key, required this.openSession});

  final AppSessionOpener openSession;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tarkov Companion',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: AppRoot(openSession: openSession),
    );
  }
}
