import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

/// The primary navigation shell shown once game data is available.
///
/// Layout:
///
/// * at 700 logical pixels and wider, a persistent [NavigationRail] sits left
///   of the content, which is the Linux desktop layout;
/// * below 700, the same destinations move to a bottom [NavigationBar] for the
///   future phone layout.
///
/// The two tabs live in an [IndexedStack], so both screens stay mounted while
/// the other is hidden. Search text, filters, scroll position and a pending
/// debounce therefore survive a tab switch; the shell never rebuilds a screen
/// from scratch. Both queries run once on first build because both tabs are
/// created eagerly, which is cheap against the local database and is what makes
/// the preserved state possible.
///
/// The app bar title follows the selected tab. Rows are routed here, not in the
/// feature screens: an item tap pushes [ItemDetailScreen] and a quest tap pushes
/// [QuestDetailScreen]. [onQuestSelected] is a test seam that overrides the
/// default navigation when supplied.
///
/// When [profileServices] is supplied a third **Profiles** destination appears.
/// It renders [ProfilesScreen] and reports the active profile back here, so the
/// Quests tab switches to the new profile and refreshes its derived
/// availability without an app restart. Without the services the shell keeps
/// its original two tabs, which is what lets the shell tests build a session
/// with no profile wiring.
///
/// A footer below the body carries the background update status, the schedule
/// and **Check now**, plus the entry point to [AboutScreen]. Keeping these out
/// of the rail leaves the primary destinations (Items, Quests, Profiles) on one
/// consistent line and gives update errors a non-modal place to appear.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.catalog,
    this.quests,
    this.activeProfileId,
    this.profileServices,
    this.updates,
    this.dataBundle,
    this.upstreamCheck,
    this.imageCache,
    this.appVersion = '0.1.0',
    this.onQuestSelected,
  });

  /// Query facade for the catalog. Null only in shell tests that build a
  /// session without SQLite; the production session always provides it.
  final CatalogRepository? catalog;

  /// Query facade for the quest list. Null for the same reason.
  final QuestRepository? quests;

  /// Profile whose progress supplies quest state badges.
  final String? activeProfileId;

  /// Profile management services; when present the shell adds the Profiles
  /// tab. Production passes the session value, shell tests leave it null.
  final ProfileServices? profileServices;

  /// Background update controls and status, when the session has them.
  ///
  /// Null keeps the footer to the About entry only, which is what shell tests
  /// without a scheduler use.
  final UpdateCheckControl? updates;

  /// Locally applied data summary shown on the About screen.
  final DataBundleStatus? dataBundle;

  /// Set when the shell can check the upstream without blocking local data.
  ///
  /// Production adapts `SyncService.prepare`; tests and sessions without a
  /// network seam leave it null, which keeps the catalog and quests offline
  /// strip dormant.
  final UpstreamCheck? upstreamCheck;

  /// Disk-backed item artwork cache shared by the list and detail routes.
  ///
  /// Null keeps placeholders, which is what shell tests without a network
  /// seam use.
  final ItemImageCache? imageCache;

  /// Version written into exported progress files and shown on About.
  final String appVersion;

  /// Test seam: when supplied, a quest tap reports the id instead of pushing
  /// [QuestDetailScreen]. Production leaves it null.
  final ValueChanged<String>? onQuestSelected;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Windows narrower than this use the bottom bar.
  static const double _railBreakpoint = 700;

  _HomeTab _tab = _HomeTab.items;
  late String? _activeProfileId = widget.activeProfileId;

  /// Bumped on every profile change so the mounted Quests tab re-derives
  /// availability (a level edit keeps the same profile id).
  int _profileRevision = 0;

  List<_HomeTab> get _tabs => <_HomeTab>[
    _HomeTab.items,
    _HomeTab.quests,
    if (widget.profileServices != null) _HomeTab.profiles,
  ];

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeProfileId != oldWidget.activeProfileId) {
      _activeProfileId = widget.activeProfileId;
    }
    if (_tabs.contains(_tab) == false) {
      _tab = _HomeTab.items;
    }
  }

  void _selectTab(int index) {
    final tabs = _tabs;
    if (index < 0 || index >= tabs.length) {
      return;
    }
    final next = tabs[index];
    if (next == _tab) {
      return;
    }
    setState(() => _tab = next);
  }

  void _onProfileChanged(Profile? active) {
    setState(() {
      _activeProfileId = active?.id;
      _profileRevision++;
    });
  }

  void _openItem(String itemId) {
    final catalog = widget.catalog;
    if (catalog == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemDetailScreen(
          repository: catalog,
          itemId: itemId,
          upstreamCheck: widget.upstreamCheck,
          imageCache: widget.imageCache,
        ),
      ),
    );
  }

  void _openAbout() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AboutScreen(appVersion: widget.appVersion, data: widget.dataBundle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _railBreakpoint;
    final tabs = _tabs;
    final body = IndexedStack(
      index: tabs.indexOf(_tab),
      children: <Widget>[
        KeyedSubtree(key: const Key('home-items-tab'), child: _buildItemsTab()),
        KeyedSubtree(
          key: Key('home-quests-tab-$_profileRevision'),
          child: _buildQuestsTab(),
        ),
        if (widget.profileServices != null)
          KeyedSubtree(
            key: const Key('home-profiles-tab'),
            child: _buildProfilesTab(),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(_tab.label, key: const Key('home-tab-title'))),
      body: Column(
        children: <Widget>[
          Expanded(
            child: wide
                ? Row(
                    children: <Widget>[
                      NavigationRail(
                        key: const Key('home-navigation-rail'),
                        selectedIndex: tabs.indexOf(_tab),
                        onDestinationSelected: _selectTab,
                        labelType: NavigationRailLabelType.all,
                        destinations: <NavigationRailDestination>[
                          const NavigationRailDestination(
                            icon: Icon(Icons.inventory_2_outlined),
                            selectedIcon: Icon(Icons.inventory_2),
                            label: Text(
                              'Items',
                              key: Key('home-rail-items-label'),
                            ),
                          ),
                          const NavigationRailDestination(
                            icon: Icon(Icons.checklist_outlined),
                            selectedIcon: Icon(Icons.checklist),
                            label: Text(
                              'Quests',
                              key: Key('home-rail-quests-label'),
                            ),
                          ),
                          if (widget.profileServices != null)
                            const NavigationRailDestination(
                              icon: Icon(Icons.person_outline),
                              selectedIcon: Icon(Icons.person),
                              label: Text(
                                'Profiles',
                                key: Key('home-rail-profiles-label'),
                              ),
                            ),
                        ],
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: body),
                    ],
                  )
                : body,
          ),
          _buildFooter(),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              key: const Key('home-bottom-navigation'),
              selectedIndex: tabs.indexOf(_tab),
              onDestinationSelected: _selectTab,
              destinations: <NavigationDestination>[
                const NavigationDestination(
                  key: Key('home-bar-items'),
                  icon: Icon(Icons.inventory_2_outlined),
                  selectedIcon: Icon(Icons.inventory_2),
                  label: 'Items',
                ),
                const NavigationDestination(
                  key: Key('home-bar-quests'),
                  icon: Icon(Icons.checklist_outlined),
                  selectedIcon: Icon(Icons.checklist),
                  label: 'Quests',
                ),
                if (widget.profileServices != null)
                  const NavigationDestination(
                    key: Key('home-bar-profiles'),
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: 'Profiles',
                  ),
              ],
            ),
    );
  }

  /// The footer status area shared by the rail and bottom-bar layouts.
  ///
  /// About is always present so the attribution and licence are reachable even
  /// from a session without update services. The sync strip is added when the
  /// session supplies a controller.
  Widget _buildFooter() {
    final updates = widget.updates;
    if (updates != null) {
      return SyncStatusBar(control: updates, onAbout: _openAbout);
    }

    final tokens = AppTokens.of(context);
    return Container(
      key: const Key('home-footer'),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.borderSoft)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spaceLg,
        vertical: tokens.spaceSm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            key: const Key('home-about'),
            label: 'About',
            variant: AppButtonVariant.ghost,
            onPressed: _openAbout,
          ),
        ],
      ),
    );
  }

  Widget _buildItemsTab() {
    final catalog = widget.catalog;
    if (catalog == null) {
      return const _TabUnavailable(
        message: 'The item catalog is not available in this session.',
      );
    }
    return CatalogScreen(
      repository: catalog,
      onItemSelected: _openItem,
      upstreamCheck: widget.upstreamCheck,
      imageCache: widget.imageCache,
    );
  }

  Widget _buildQuestsTab() {
    final quests = widget.quests;
    if (quests == null) {
      return const _TabUnavailable(
        message: 'The quest catalog is not available in this session.',
      );
    }
    return QuestListScreen(
      repository: quests,
      profileId: _activeProfileId,
      onQuestSelected: widget.onQuestSelected ?? _openQuest,
      upstreamCheck: widget.upstreamCheck,
    );
  }

  Widget _buildProfilesTab() {
    return ProfilesScreen(
      services: widget.profileServices!,
      appVersion: widget.appVersion,
      onProfileChanged: _onProfileChanged,
    );
  }

  void _openQuest(String questId) {
    final catalog = widget.catalog;
    final quests = widget.quests;
    if (catalog == null || quests == null) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuestDetailScreen(
          repository: quests,
          catalog: catalog,
          questId: questId,
          profileId: _activeProfileId,
          upstreamCheck: widget.upstreamCheck,
        ),
      ),
    );
  }
}

enum _HomeTab {
  items('Items'),
  quests('Quests'),
  profiles('Profiles');

  const _HomeTab(this.label);

  final String label;
}

/// Placeholder body for a tab whose repository is missing.
///
/// Only shells built without SQLite see this; a production session always has
/// both repositories.
class _TabUnavailable extends StatelessWidget {
  const _TabUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ),
    );
  }
}
