import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import '../section_header.dart';

/// The full item detail view.
///
/// The screen reads one [ItemDetail] through [CatalogRepository] and renders a
/// header, the base properties every item has, and one type-specific section.
/// Sections and rows are built from the typed [ItemProperties] subclass, so a
/// property that does not apply to the item's kind cannot reach the tree: a
/// weapon never shows damage, ammunition never shows ergonomics, and a
/// barter-only item gets no type-specific section at all. No row is rendered
/// as zero or "N/A".
///
/// Images are a fixed neutral placeholder until task 5.6 adds the image cache.
/// Acquisition/disposition (5.4), prices (5.5/5.7) and history are deliberately
/// absent.
class ItemDetailScreen extends StatefulWidget {
  const ItemDetailScreen({
    super.key,
    required this.repository,
    required this.itemId,
    this.onBack,
  });

  final CatalogRepository repository;

  /// Upstream item id to resolve.
  final String itemId;

  /// Called by the not-found back action. When omitted, the screen pops the
  /// current route, which is the normal behavior for a pushed detail page.
  final VoidCallback? onBack;

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  ItemDetail? _detail;
  Object? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ItemDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemId != widget.itemId ||
        oldWidget.repository != widget.repository) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _detail = null;
      _error = null;
    });
    try {
      final detail = await widget.repository.itemDetail(widget.itemId);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  void _back() {
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      key: const Key('item-detail-screen'),
      appBar: AppBar(title: Text(detail?.name ?? 'Item detail')),
      body: SafeArea(child: _buildBody(detail)),
    );
  }

  Widget _buildBody(ItemDetail? detail) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(key: Key('item-detail-loading')),
      );
    }
    final error = _error;
    if (error != null) {
      return _ErrorState(error: error, onRetry: _load);
    }
    if (detail == null) {
      return _NotFoundState(itemId: widget.itemId, onBack: _back);
    }
    return _DetailBody(detail: detail);
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail});

  final ItemDetail detail;

  @override
  Widget build(BuildContext context) {
    final typed = _buildTypedSection(detail.properties);
    return SingleChildScrollView(
      key: const Key('item-detail-scroll'),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(detail: detail),
              const SizedBox(height: 24),
              _DetailSection(
                title: 'Properties',
                children: [
                  if (detail.weight != null)
                    _PropertyRow(
                      label: 'Weight',
                      value: '${_formatNumber(detail.weight!)} kg',
                    ),
                  if (detail.gridSize != null)
                    _PropertyRow(
                      label: 'Grid size',
                      value: '${detail.gridSize} slots',
                    ),
                  if (detail.stackMaxSize != null)
                    _PropertyRow(
                      label: 'Stack limit',
                      value: '${detail.stackMaxSize}',
                    ),
                ],
              ),
              if (detail.categories.isNotEmpty) ...[
                const SizedBox(height: 24),
                _DetailSection(
                  title: 'Categories',
                  children: [
                    Wrap(
                      key: const Key('item-detail-categories'),
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final category in detail.categories)
                          Chip(
                            label: Text(category.name),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                ),
              ],
              if (detail.wikiLink != null || detail.link != null) ...[
                const SizedBox(height: 24),
                _DetailSection(
                  title: 'Links',
                  children: [
                    if (detail.wikiLink != null)
                      _PropertyRow(
                        label: 'Wiki',
                        child: SelectableText(
                          detail.wikiLink!,
                          key: const Key('item-detail-wiki-link'),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ),
                    if (detail.link != null)
                      _PropertyRow(
                        label: 'Page',
                        child: SelectableText(
                          detail.link!,
                          key: const Key('item-detail-page-link'),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ),
                  ],
                ),
              ],
              if (typed != null) ...[const SizedBox(height: 24), typed],
              if (detail.description != null) ...[
                const SizedBox(height: 24),
                _DetailSection(
                  title: 'Description',
                  children: [
                    Text(
                      detail.description!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildTypedSection(ItemProperties properties) {
    return switch (properties) {
      WeaponProperties() => _WeaponSection(properties: properties),
      AmmunitionProperties() => _AmmunitionSection(properties: properties),
      ArmorProperties() => _ArmorSection(properties: properties),
      MedicalProperties() => _MedicalSection(properties: properties),
      GenericProperties() => null,
    };
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detail});

  final ItemDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const Key('item-detail-icon-placeholder'),
          width: 128,
          height: 128,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.inventory_2_outlined,
            size: 56,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.name,
                key: const Key('item-detail-name'),
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                detail.shortName,
                key: const Key('item-detail-short-name'),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final type in detail.types)
                    Chip(
                      label: Text(humanizeLabel(type)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeaponSection extends StatelessWidget {
  const _WeaponSection({required this.properties});

  final WeaponProperties properties;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final caliber = properties.caliber;
    if (caliber != null) {
      rows.add(_PropertyRow(label: 'Caliber', value: formatCaliber(caliber)));
    }
    if (properties.fireRate != null) {
      rows.add(
        _PropertyRow(label: 'Fire rate', value: '${properties.fireRate} rpm'),
      );
    }
    if (properties.ergonomics != null) {
      rows.add(
        _PropertyRow(label: 'Ergonomics', value: '${properties.ergonomics}'),
      );
    }
    final recoil = _formatRecoil(properties);
    if (recoil != null) {
      rows.add(_PropertyRow(label: 'Recoil', value: recoil));
    }
    if (properties.effectiveDistance != null) {
      rows.add(
        _PropertyRow(
          label: 'Effective range',
          value: '${properties.effectiveDistance} m',
        ),
      );
    }
    if (properties.fireModes.isNotEmpty) {
      rows.add(
        _PropertyRow(
          label: 'Fire modes',
          value: properties.fireModes.join(' · '),
        ),
      );
    }
    if (properties.slots.isNotEmpty) {
      rows.add(
        _PropertyRow(
          label: 'Compatible slots',
          child: Wrap(
            key: const Key('item-detail-weapon-slots'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final slot in properties.slots)
                Chip(
                  label: Text(
                    slot.required ? '${slot.name} · required' : slot.name,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
      );
    }
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return _DetailSection(
      key: const Key('item-detail-section-weapon'),
      title: 'Weapon',
      children: rows,
    );
  }

  static String? _formatRecoil(WeaponProperties properties) {
    final vertical = properties.recoilVertical;
    final horizontal = properties.recoilHorizontal;
    if (vertical != null && horizontal != null) {
      return 'Vertical $vertical · Horizontal $horizontal';
    }
    if (vertical != null) {
      return 'Vertical $vertical';
    }
    if (horizontal != null) {
      return 'Horizontal $horizontal';
    }
    return null;
  }
}

class _AmmunitionSection extends StatelessWidget {
  const _AmmunitionSection({required this.properties});

  final AmmunitionProperties properties;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final caliber = properties.caliber;
    if (caliber != null) {
      rows.add(_PropertyRow(label: 'Caliber', value: formatCaliber(caliber)));
    }
    if (properties.damage != null) {
      rows.add(_PropertyRow(label: 'Damage', value: '${properties.damage}'));
    }
    if (properties.penetrationPower != null) {
      rows.add(
        _PropertyRow(
          label: 'Penetration',
          value: '${properties.penetrationPower}',
        ),
      );
    }
    if (properties.armorDamage != null) {
      rows.add(
        _PropertyRow(label: 'Armor damage', value: '${properties.armorDamage}'),
      );
    }
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return _DetailSection(
      key: const Key('item-detail-section-ammunition'),
      title: 'Ammunition',
      children: rows,
    );
  }
}

class _ArmorSection extends StatelessWidget {
  const _ArmorSection({required this.properties});

  final ArmorProperties properties;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (properties.armorClass != null) {
      rows.add(
        _PropertyRow(label: 'Class', value: 'Class ${properties.armorClass}'),
      );
    }
    if (properties.durability != null) {
      rows.add(
        _PropertyRow(label: 'Durability', value: '${properties.durability}'),
      );
    }
    if (properties.zones.isNotEmpty) {
      rows.add(
        _PropertyRow(
          label: 'Protected zones',
          value: properties.zones.join(', '),
        ),
      );
    }
    if (properties.material != null) {
      rows.add(
        _PropertyRow(
          label: 'Material',
          value: humanizeLabel(properties.material!),
        ),
      );
    }
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return _DetailSection(
      key: const Key('item-detail-section-armor'),
      title: 'Armor',
      children: rows,
    );
  }
}

class _MedicalSection extends StatelessWidget {
  const _MedicalSection({required this.properties});

  final MedicalProperties properties;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (properties.uses != null) {
      rows.add(_PropertyRow(label: 'Uses', value: '${properties.uses}'));
    }
    final healing = _formatHealing(properties);
    if (healing != null) {
      rows.add(_PropertyRow(label: 'Healing', value: healing));
    }
    final effects = _formatEffects(properties);
    if (effects != null) {
      rows.add(_PropertyRow(label: 'Effects', value: effects));
    }
    if (properties.useTime != null) {
      rows.add(
        _PropertyRow(
          label: 'Use time',
          value: '${_formatNumber(properties.useTime!)} s',
        ),
      );
    }
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return _DetailSection(
      key: const Key('item-detail-section-medical'),
      title: 'Medical',
      children: rows,
    );
  }

  static String? _formatHealing(MedicalProperties properties) {
    final parts = <String>[
      if (properties.hitpoints != null) '${properties.hitpoints} HP',
      if (properties.maxHealPerUse != null)
        '${properties.maxHealPerUse} HP per use',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String? _formatEffects(MedicalProperties properties) {
    final effects = <String>[
      for (final cure in properties.cures) humanizeLabel(cure),
      for (final stim in properties.stimEffects)
        if (stim.type != null) humanizeLabel(stim.type!),
    ];
    return effects.isEmpty ? null : effects.join(', ');
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

/// One label/value row. A caller only adds a row when it has a value; [value]
/// and [child] are therefore never an "N/A" fallback.
class _PropertyRow extends StatelessWidget {
  const _PropertyRow({required this.label, this.value, this.child});

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child:
                child ?? Text(value ?? '', style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _NotFoundState extends StatelessWidget {
  const _NotFoundState({required this.itemId, required this.onBack});

  final String itemId;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Item no longer available',
              key: const Key('item-detail-not-found'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Item $itemId is not in the current dataset. It may have been '
              'removed upstream.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              key: const Key('item-detail-back'),
              onPressed: onBack,
              child: const Text('Back to catalog'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              'Could not load this item.',
              key: const Key('item-detail-error'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '$error',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('item-detail-retry'),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Turns a bundle token into a display label (`noFlea` -> `No flea`,
/// `LightBleeding` -> `Light bleeding`).
String humanizeLabel(String value) {
  final spaced = value
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
  if (spaced.isEmpty) {
    return value;
  }
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// Formats a bundle caliber id (`Caliber556x45NATO` -> `5.56x45 NATO`).
String formatCaliber(String value) {
  final raw = value.startsWith('Caliber')
      ? value.substring('Caliber'.length)
      : value;
  final match = RegExp(r'^(\d+)x(\d+)(.*)$').firstMatch(raw);
  if (match == null) {
    return humanizeLabel(raw);
  }
  final first = _caliberNumber(int.parse(match.group(1)!));
  final second = _caliberNumber(int.parse(match.group(2)!));
  final suffix = match.group(3)!.trim();
  return suffix.isEmpty ? '${first}x$second' : '${first}x$second $suffix';
}

String _caliberNumber(int value) {
  if (value < 100) {
    return '$value';
  }
  return (value / 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
