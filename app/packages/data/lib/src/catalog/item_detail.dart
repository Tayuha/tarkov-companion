import 'dart:convert';

/// One item with everything the detail view renders.
///
/// The catalog keeps the scalar columns in `items` and the complete bundle
/// record in `payload`; this class reads both once and exposes typed,
/// presentation-ready values. Type-specific properties are a closed set of
/// subclasses, so a detail screen can switch on [properties] exhaustively and
/// a property that does not apply to an item type simply does not exist on its
/// object. That is the data half of the "omit instead of N/A" rule.
final class ItemDetail {
  const ItemDetail._({
    required this.id,
    required this.name,
    required this.shortName,
    required this.description,
    required this.weight,
    required this.width,
    required this.height,
    required this.stackMaxSize,
    required this.wikiLink,
    required this.link,
    required this.types,
    required this.categories,
    required this.conflictingItemIds,
    required this.conflictingSlotIds,
    required this.properties,
    required this.price,
    required this.basePrice,
    required this.iconLink,
  });

  /// Decodes the canonical bundle `payload` and combines it with the indexed
  /// columns and tag rows.
  ///
  /// [categoryNames] maps a category id to the display name from the bundle's
  /// `itemCategory`/`handbookCategory` records. A missing name falls back to
  /// the id, so a partial dataset never hides the category.
  ///
  /// Throws a [FormatException] when [payload] is not a JSON object; the
  /// repository returns `null` only for an unknown id, and the screen shows its
  /// error state for corrupt data.
  factory ItemDetail.fromPayload({
    required String id,
    required String name,
    required String shortName,
    required double? weight,
    required int? width,
    required int? height,
    required String payload,
    required List<String> types,
    required List<String> categoryIds,
    required List<String> handbookCategoryIds,
    Map<String, String> categoryNames = const {},
  }) {
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Item payload is not a JSON object.');
    }

    final properties = _map(decoded['properties']);
    final categories = <ItemCategoryLabel>[];
    final seen = <String>{};
    for (final categoryId in [...categoryIds, ...handbookCategoryIds]) {
      if (categoryId.isEmpty || !seen.add(categoryId)) {
        continue;
      }
      categories.add(
        ItemCategoryLabel(
          id: categoryId,
          name: categoryNames[categoryId] ?? categoryId,
        ),
      );
    }

    final wikiLink = _text(decoded['wikiLink']);
    final link = _text(decoded['link']);

    return ItemDetail._(
      id: id,
      name: name,
      shortName: shortName,
      description: _text(decoded['description']),
      weight: weight,
      width: width,
      height: height,
      stackMaxSize: _positiveInt(decoded['stackMaxSize']),
      wikiLink: wikiLink,
      link: link,
      types: List.unmodifiable(types),
      categories: List.unmodifiable(categories),
      conflictingItemIds: List.unmodifiable(
        _strings(decoded['conflictingItemIds']),
      ),
      conflictingSlotIds: List.unmodifiable(
        _strings(decoded['conflictingSlotIds']),
      ),
      properties: _parseProperties(properties, types),
      price: _parsePrice(decoded['price']),
      basePrice: _nonNegativeInt(decoded['basePrice']),
      iconLink: _text(decoded['iconLink']),
    );
  }

  final String id;
  final String name;
  final String shortName;

  /// Localized description, or `null` when the bundle has none.
  final String? description;

  /// Weight in kilograms.
  final double? weight;

  /// Grid width in slots.
  final int? width;

  /// Grid height in slots.
  final int? height;

  /// Maximum stack size, when the bundle provides one.
  final int? stackMaxSize;

  /// Escape from Tarkov wiki URL, or `null` when the item has no page.
  final String? wikiLink;

  /// tarkov.dev page URL, or `null` when the item has no page.
  final String? link;

  /// Bundle `types[]`, in bundle order.
  final List<String> types;

  /// Categories from both trees, with display names when the dataset has them.
  final List<ItemCategoryLabel> categories;

  final List<String> conflictingItemIds;
  final List<String> conflictingSlotIds;

  /// The typed property set for this item's kind.
  final ItemProperties properties;

  /// The bundle's price snapshot, or [ItemPrice.none] when the record has no
  /// `price` object.
  final ItemPrice price;

  /// Trader-independent base price in roubles, `basePrice`.
  final int? basePrice;

  /// Item icon URL (`iconLink`), or `null` when the bundle has none.
  final String? iconLink;

  /// Whether the item may appear on the flea market (`types` excludes
  /// `noFlea`). Used by the price section to explain a missing flea price
  /// instead of presenting it as zero.
  bool get fleaEligible => !types.contains('noFlea');

  /// `width` × `height` in slots, or `null` when the bundle has no grid.
  String? get gridSize {
    final w = width;
    final h = height;
    if (w == null || h == null) {
      return null;
    }
    return '$w × $h';
  }
}

/// The bundle `price` snapshot for an item.
///
/// Every field is nullable because the bundle can carry a partial observation:
/// a trader-only item has no flea fields, and a zero [`fleaLastLow`] is a real
/// observation (no active offers) rather than a missing one. The price section
/// distinguishes those states instead of collapsing them into `null`.
final class ItemPrice {
  const ItemPrice({
    required this.fleaLastLow,
    required this.fleaAvg24h,
    required this.change48hPercent,
    required this.change48hAbsolute,
    required this.observedAt,
  });

  /// No price object in the bundle.
  static const none = ItemPrice(
    fleaLastLow: null,
    fleaAvg24h: null,
    change48hPercent: null,
    change48hAbsolute: null,
    observedAt: null,
  );

  /// Latest flea-market low, `price.lastLow`.
  final int? fleaLastLow;

  /// Flea-market 24 h average, `price.avg24h`.
  final int? fleaAvg24h;

  /// 48 h flea price change as a percentage, `price.change48hPercent`.
  final double? change48hPercent;

  /// 48 h flea price change in roubles, `price.change48h`.
  final int? change48hAbsolute;

  /// When the snapshot was observed, `price.observedAt`.
  final DateTime? observedAt;

  /// Whether the bundle carried any flea price field.
  bool get hasFleaObservation => fleaLastLow != null || fleaAvg24h != null;

  /// Whether the latest low is a real zero (no active offers).
  bool get isZero => fleaLastLow == 0;

  /// No fields were present at all.
  bool get isEmpty =>
      fleaLastLow == null && fleaAvg24h == null && observedAt == null;
}

/// A category label for the detail header.
final class ItemCategoryLabel {
  const ItemCategoryLabel({required this.id, required this.name});

  final String id;
  final String name;
}

/// Type-specific item properties.
///
/// Every subclass only declares fields that apply to that kind, so a missing
/// field is not a `null` to render — the field does not exist.
sealed class ItemProperties {
  const ItemProperties();
}

/// A weapon's combat properties (`ItemPropertiesWeapon`).
final class WeaponProperties extends ItemProperties {
  const WeaponProperties({
    required this.caliber,
    required this.fireRate,
    required this.ergonomics,
    required this.recoilVertical,
    required this.recoilHorizontal,
    required this.effectiveDistance,
    required this.fireModes,
    required this.slots,
  });

  /// Bundle caliber id (`Caliber556x45NATO`); the UI humanizes it.
  final String? caliber;
  final int? fireRate;
  final int? ergonomics;
  final int? recoilVertical;
  final int? recoilHorizontal;
  final int? effectiveDistance;
  final List<String> fireModes;
  final List<WeaponSlot> slots;
}

/// One attachment slot of a weapon.
final class WeaponSlot {
  const WeaponSlot({
    required this.id,
    required this.name,
    required this.required,
  });

  final String id;
  final String name;
  final bool required;
}

/// A cartridge's ballistic properties (`ItemPropertiesAmmo`).
final class AmmunitionProperties extends ItemProperties {
  const AmmunitionProperties({
    required this.caliber,
    required this.damage,
    required this.penetrationPower,
    required this.armorDamage,
  });

  final String? caliber;
  final int? damage;
  final int? penetrationPower;
  final int? armorDamage;
}

/// Body armor and helmet protection (`ItemPropertiesArmor`/`Helmet`).
final class ArmorProperties extends ItemProperties {
  const ArmorProperties({
    required this.armorClass,
    required this.durability,
    required this.zones,
    required this.material,
  });

  final int? armorClass;
  final int? durability;
  final List<String> zones;
  final String? material;
}

/// Medical, stim and surgical item properties.
final class MedicalProperties extends ItemProperties {
  const MedicalProperties({
    required this.uses,
    required this.hitpoints,
    required this.maxHealPerUse,
    required this.useTime,
    required this.cures,
    required this.stimEffects,
  });

  /// Consumable uses, or `null` for a kit measured in hit points.
  final int? uses;

  /// Total healing pool in hit points (medkits).
  final int? hitpoints;

  /// Hit points restored per use (medkits).
  final int? maxHealPerUse;

  /// Seconds the use animation takes.
  final double? useTime;

  /// Conditions the item treats (`LightBleeding`, `Pain`, ...).
  final List<String> cures;

  /// Stim buffs; empty for a plain medical item.
  final List<StimEffect> stimEffects;
}

/// One stim buff entry.
final class StimEffect {
  const StimEffect({
    required this.type,
    required this.duration,
    required this.value,
  });

  final String? type;
  final int? duration;
  final num? value;
}

/// Properties for a kind that has no dedicated section (keys, mods, barter).
///
/// The detail view renders only the base properties for these items.
final class GenericProperties extends ItemProperties {
  const GenericProperties();
}

ItemProperties _parseProperties(
  Map<String, Object?> properties,
  List<String> types,
) {
  if (properties.isEmpty) {
    return const GenericProperties();
  }

  final propertiesType = _text(properties['propertiesType']);
  if (types.contains('gun') || propertiesType == 'ItemPropertiesWeapon') {
    return WeaponProperties(
      caliber: _text(properties['caliber']),
      fireRate: _positiveInt(properties['fireRate']),
      ergonomics: _int(properties['ergonomics']),
      recoilVertical: _positiveInt(properties['recoilVertical']),
      recoilHorizontal: _positiveInt(properties['recoilHorizontal']),
      effectiveDistance: _positiveInt(properties['effectiveDistance']),
      fireModes: List.unmodifiable(_strings(properties['fireModes'])),
      slots: List.unmodifiable([
        for (final slot in _list(properties['slots']))
          if (_map(slot) case final map when _text(map['name']) != null)
            WeaponSlot(
              id: _text(map['id']) ?? '',
              name: _text(map['name'])!,
              required: map['required'] == true,
            ),
      ]),
    );
  }

  if (propertiesType == 'ItemPropertiesAmmo' ||
      (types.contains('ammo') &&
          properties.containsKey('damage') &&
          properties.containsKey('penetrationPower'))) {
    return AmmunitionProperties(
      caliber: _text(properties['caliber']),
      damage: _positiveInt(properties['damage']),
      penetrationPower: _positiveInt(properties['penetrationPower']),
      armorDamage: _positiveInt(properties['armorDamage']),
    );
  }

  if (types.contains('armor') ||
      types.contains('helmet') ||
      propertiesType == 'ItemPropertiesArmor' ||
      propertiesType == 'ItemPropertiesArmorAttachment') {
    return ArmorProperties(
      armorClass: _positiveInt(properties['class']),
      durability: _positiveInt(properties['durability']),
      zones: List.unmodifiable(_unique(_strings(properties['zones']))),
      material: _text(properties['material']),
    );
  }

  if (types.contains('meds') ||
      types.contains('injectors') ||
      (propertiesType?.startsWith('ItemPropertiesMedical') ?? false) ||
      propertiesType == 'ItemPropertiesMedKit' ||
      propertiesType == 'ItemPropertiesPainkiller' ||
      propertiesType == 'ItemPropertiesStim' ||
      propertiesType == 'ItemPropertiesSurgicalKit') {
    return MedicalProperties(
      uses: _positiveInt(properties['uses']),
      hitpoints: _positiveInt(properties['hitpoints']),
      maxHealPerUse: _positiveInt(properties['maxHealPerUse']),
      useTime: _positiveDouble(properties['useTime']),
      cures: List.unmodifiable(_unique(_strings(properties['cures']))),
      stimEffects: List.unmodifiable([
        for (final effect in _list(properties['stimEffects']))
          if (_map(effect) case final map when map.isNotEmpty)
            StimEffect(
              type: _text(map['type']),
              duration: _positiveInt(map['duration']),
              value: _num(map['value']),
            ),
      ]),
    );
  }

  return const GenericProperties();
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return const {};
}

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _strings(Object? value) => [
  for (final entry in _list(value))
    if (entry is String && entry.trim().isNotEmpty) entry,
];

List<String> _unique(List<String> values) {
  final seen = <String>{};
  return [
    for (final value in values)
      if (seen.add(value)) value,
  ];
}

String? _text(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return null;
}

int? _positiveInt(Object? value) {
  final parsed = _int(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

double? _positiveDouble(Object? value) {
  final parsed = _num(value)?.toDouble();
  return parsed != null && parsed > 0 ? parsed : null;
}

num? _num(Object? value) => value is num ? value : null;

ItemPrice _parsePrice(Object? value) {
  final price = _map(value);
  if (price.isEmpty) {
    return ItemPrice.none;
  }
  return ItemPrice(
    fleaLastLow: _nonNegativeInt(price['lastLow']),
    fleaAvg24h: _nonNegativeInt(price['avg24h']),
    change48hPercent: _num(price['change48hPercent'])?.toDouble(),
    change48hAbsolute: _int(price['change48h']),
    observedAt: _dateTime(price['observedAt']),
  );
}

int? _nonNegativeInt(Object? value) {
  final parsed = _int(value);
  return parsed != null && parsed >= 0 ? parsed : null;
}

DateTime? _dateTime(Object? value) {
  final text = _text(value);
  if (text == null) {
    return null;
  }
  return DateTime.tryParse(text)?.toUtc();
}
