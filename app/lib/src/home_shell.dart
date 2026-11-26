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
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.catalog,
    this.quests,
    this.activeProfileId,
    this.onQuestSelected,
  });

  /// Query facade for the catalog. Null only in shell tests that build a
  /// session without SQLite; the production session always provides it.
  final CatalogRepository? catalog;

  /// Query facade for the quest list. Null for the same reason.
  final QuestRepository? quests;

  /// Profile whose progress supplies quest state badges.
  final String? activeProfileId;

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

  void _selectTab(int index) {
    final next = _HomeTab.values[index];
    if (next == _tab) {
      return;
    }
    setState(() => _tab = next);
  }

  void _openItem(String itemId) {
    final catalog = widget.catalog;
    if (catalog == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemDetailScreen(repository: catalog, itemId: itemId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _railBreakpoint;
    final body = IndexedStack(
      index: _tab.index,
      children: <Widget>[
        KeyedSubtree(key: const Key('home-items-tab'), child: _buildItemsTab()),
        KeyedSubtree(
          key: const Key('home-quests-tab'),
          child: _buildQuestsTab(),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(_tab.label, key: const Key('home-tab-title'))),
      body: wide
          ? Row(
              children: <Widget>[
                NavigationRail(
                  key: const Key('home-navigation-rail'),
                  selectedIndex: _tab.index,
                  onDestinationSelected: _selectTab,
                  labelType: NavigationRailLabelType.all,
                  destinations: const <NavigationRailDestination>[
                    NavigationRailDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      selectedIcon: Icon(Icons.inventory_2),
                      label: Text('Items', key: Key('home-rail-items-label')),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.checklist_outlined),
                      selectedIcon: Icon(Icons.checklist),
                      label: Text('Quests', key: Key('home-rail-quests-label')),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              key: const Key('home-bottom-navigation'),
              selectedIndex: _tab.index,
              onDestinationSelected: _selectTab,
              destinations: const <NavigationDestination>[
                NavigationDestination(
                  key: Key('home-bar-items'),
                  icon: Icon(Icons.inventory_2_outlined),
                  selectedIcon: Icon(Icons.inventory_2),
                  label: 'Items',
                ),
                NavigationDestination(
                  key: Key('home-bar-quests'),
                  icon: Icon(Icons.checklist_outlined),
                  selectedIcon: Icon(Icons.checklist),
                  label: 'Quests',
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
    return CatalogScreen(repository: catalog, onItemSelected: _openItem);
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
      profileId: widget.activeProfileId,
      onQuestSelected: widget.onQuestSelected ?? _openQuest,
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
          profileId: widget.activeProfileId,
        ),
      ),
    );
  }
}

enum _HomeTab {
  items('Items'),
  quests('Quests');

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
