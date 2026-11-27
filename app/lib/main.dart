import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

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
///
/// Pressing Escape on a pushed page (item detail and later quest detail) pops
/// it through the standard [Navigator]. Escape on the root route falls through
/// to the default Flutter dismissal handling, so closing a menu or a text
/// toolbar keeps working.
class TarkovCompanionApp extends StatefulWidget {
  const TarkovCompanionApp({super.key, required this.openSession});

  final AppSessionOpener openSession;

  @override
  State<TarkovCompanionApp> createState() => _TarkovCompanionAppState();
}

class _TarkovCompanionAppState extends State<TarkovCompanionApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tarkov Companion',
      navigatorKey: _navigatorKey,
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      builder: (context, child) {
        return Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.escape): _PopRouteIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _PopRouteIntent: _PopRouteAction(_navigatorKey),
            },
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: AppRoot(openSession: widget.openSession),
    );
  }
}

/// Asks the navigator to leave the current page.
class _PopRouteIntent extends Intent {
  const _PopRouteIntent();
}

/// Pops the current route when there is one; otherwise stays disabled so the
/// key falls through to the default Flutter shortcuts.
class _PopRouteAction extends Action<_PopRouteIntent> {
  _PopRouteAction(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  bool isEnabled(_PopRouteIntent intent) =>
      navigatorKey.currentState?.canPop() ?? false;

  @override
  Object? invoke(_PopRouteIntent intent) {
    navigatorKey.currentState?.maybePop();
    return null;
  }
}
