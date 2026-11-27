import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import 'src/app_paths.dart';
import 'src/app_root.dart';
import 'src/app_session.dart';
import 'src/deep_links.dart';
import 'src/instance_coordinator.dart';
import 'src/launch_request.dart';
import 'src/single_instance.dart';
import 'src/window_geometry_binder.dart';
import 'src/window_platform.dart';

/// Starts the desktop app.
///
/// A second launch takes the secondary branch: it forwards its item id (or a
/// plain focus request) to the running process and exits before the database
/// is opened. The primary process opens the database exactly once.
Future<void> main(List<String> arguments) async {
  final launch = LaunchRequest.parse(arguments);
  final paths = AppPaths.resolve();
  final instance = await SingleInstance.acquire(
    directory: paths.runtimeDirectory,
    message: InstanceMessage(itemId: launch.itemId),
  );

  if (!instance.isPrimary) {
    await instance.close();
    exit(0);
  }

  WidgetsFlutterBinding.ensureInitialized();
  await _runPrimary(paths: paths, launch: launch, instance: instance);
}

Future<void> _runPrimary({
  required AppPaths paths,
  required LaunchRequest launch,
  required SingleInstance instance,
}) async {
  final window = LinuxWindowPlatform();
  final geometry = WindowGeometryBinder(platform: window);
  await geometry.start();

  final inbox = DeepLinkInbox();
  final itemId = launch.itemId;
  if (itemId != null) {
    inbox.add(ItemDeepLink(itemId));
  }
  // The listener, the GTK window and the server socket keep each other alive
  // for the process lifetime; no global handle is needed.
  InstanceCoordinator(window: window, inbox: inbox).listen(instance.messages);

  runApp(
    TarkovCompanionApp(
      openSession: () async {
        final session = await openAppSession(paths: paths);
        unawaited(geometry.bind(session));
        return session;
      },
      deepLinks: inbox,
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
///
/// Item deep links arrive through [deepLinks]; [launchRequest] is the test and
/// embedder-friendly way to add one before the first frame.
class TarkovCompanionApp extends StatefulWidget {
  const TarkovCompanionApp({
    super.key,
    required this.openSession,
    this.deepLinks,
    this.launchRequest = const LaunchRequest(),
  });

  final AppSessionOpener openSession;

  /// Queue shared with the single-instance listener. A private inbox is used
  /// when omitted.
  final DeepLinkInbox? deepLinks;

  /// Item requested by this process's launch arguments.
  final LaunchRequest launchRequest;

  @override
  State<TarkovCompanionApp> createState() => _TarkovCompanionAppState();
}

class _TarkovCompanionAppState extends State<TarkovCompanionApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final DeepLinkInbox _inbox;
  late final bool _ownsInbox;

  @override
  void initState() {
    super.initState();
    _ownsInbox = widget.deepLinks == null;
    _inbox = widget.deepLinks ?? DeepLinkInbox();
    final itemId = widget.launchRequest.itemId;
    if (itemId != null) {
      _inbox.add(ItemDeepLink(itemId));
    }
  }

  @override
  void dispose() {
    if (_ownsInbox) {
      _inbox.dispose();
    }
    super.dispose();
  }

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
      home: AppRoot(openSession: widget.openSession, deepLinks: _inbox),
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
