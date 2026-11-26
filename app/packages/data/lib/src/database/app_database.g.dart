// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $DatasetStatesTable extends DatasetStates
    with TableInfo<$DatasetStatesTable, DatasetState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DatasetStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _datasetMeta = const VerificationMeta(
    'dataset',
  );
  @override
  late final GeneratedColumn<String> dataset = GeneratedColumn<String>(
    'dataset',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checksumMeta = const VerificationMeta(
    'checksum',
  );
  @override
  late final GeneratedColumn<String> checksum = GeneratedColumn<String>(
    'checksum',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schemaVersion',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordsMeta = const VerificationMeta(
    'records',
  );
  @override
  late final GeneratedColumn<int> records = GeneratedColumn<int>(
    'records',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceUpdatedAtMeta = const VerificationMeta(
    'sourceUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> sourceUpdatedAt =
      GeneratedColumn<DateTime>(
        'sourceUpdatedAt',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _appliedAtMeta = const VerificationMeta(
    'appliedAt',
  );
  @override
  late final GeneratedColumn<DateTime> appliedAt = GeneratedColumn<DateTime>(
    'appliedAt',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    mode,
    dataset,
    checksum,
    schemaVersion,
    records,
    sourceUpdatedAt,
    appliedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'datasetState';
  @override
  VerificationContext validateIntegrity(
    Insertable<DatasetState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('dataset')) {
      context.handle(
        _datasetMeta,
        dataset.isAcceptableOrUnknown(data['dataset']!, _datasetMeta),
      );
    } else if (isInserting) {
      context.missing(_datasetMeta);
    }
    if (data.containsKey('checksum')) {
      context.handle(
        _checksumMeta,
        checksum.isAcceptableOrUnknown(data['checksum']!, _checksumMeta),
      );
    } else if (isInserting) {
      context.missing(_checksumMeta);
    }
    if (data.containsKey('schemaVersion')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schemaVersion']!,
          _schemaVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_schemaVersionMeta);
    }
    if (data.containsKey('records')) {
      context.handle(
        _recordsMeta,
        records.isAcceptableOrUnknown(data['records']!, _recordsMeta),
      );
    } else if (isInserting) {
      context.missing(_recordsMeta);
    }
    if (data.containsKey('sourceUpdatedAt')) {
      context.handle(
        _sourceUpdatedAtMeta,
        sourceUpdatedAt.isAcceptableOrUnknown(
          data['sourceUpdatedAt']!,
          _sourceUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('appliedAt')) {
      context.handle(
        _appliedAtMeta,
        appliedAt.isAcceptableOrUnknown(data['appliedAt']!, _appliedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_appliedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mode, dataset};
  @override
  DatasetState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DatasetState(
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      dataset: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dataset'],
      )!,
      checksum: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checksum'],
      )!,
      schemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schemaVersion'],
      )!,
      records: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}records'],
      )!,
      sourceUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sourceUpdatedAt'],
      ),
      appliedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}appliedAt'],
      )!,
    );
  }

  @override
  $DatasetStatesTable createAlias(String alias) {
    return $DatasetStatesTable(attachedDatabase, alias);
  }
}

class DatasetState extends DataClass implements Insertable<DatasetState> {
  /// Game mode: `regular`, `pve` or `pvp-season`.
  final String mode;

  /// Bundle dataset name: `items`, `tasks`, `traders`, ...
  final String dataset;

  /// SHA-256 of the compressed dataset file that was applied.
  final String checksum;

  /// `datasets[].schemaVersion` of the applied bundle entry.
  final int schemaVersion;

  /// Number of JSONL records applied, for diagnostics.
  final int records;

  /// Upstream timestamp of the applied content, when the manifest provides it.
  final DateTime? sourceUpdatedAt;

  /// When this client applied the dataset.
  final DateTime appliedAt;
  const DatasetState({
    required this.mode,
    required this.dataset,
    required this.checksum,
    required this.schemaVersion,
    required this.records,
    this.sourceUpdatedAt,
    required this.appliedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['mode'] = Variable<String>(mode);
    map['dataset'] = Variable<String>(dataset);
    map['checksum'] = Variable<String>(checksum);
    map['schemaVersion'] = Variable<int>(schemaVersion);
    map['records'] = Variable<int>(records);
    if (!nullToAbsent || sourceUpdatedAt != null) {
      map['sourceUpdatedAt'] = Variable<DateTime>(sourceUpdatedAt);
    }
    map['appliedAt'] = Variable<DateTime>(appliedAt);
    return map;
  }

  DatasetStatesCompanion toCompanion(bool nullToAbsent) {
    return DatasetStatesCompanion(
      mode: Value(mode),
      dataset: Value(dataset),
      checksum: Value(checksum),
      schemaVersion: Value(schemaVersion),
      records: Value(records),
      sourceUpdatedAt: sourceUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceUpdatedAt),
      appliedAt: Value(appliedAt),
    );
  }

  factory DatasetState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DatasetState(
      mode: serializer.fromJson<String>(json['mode']),
      dataset: serializer.fromJson<String>(json['dataset']),
      checksum: serializer.fromJson<String>(json['checksum']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      records: serializer.fromJson<int>(json['records']),
      sourceUpdatedAt: serializer.fromJson<DateTime?>(json['sourceUpdatedAt']),
      appliedAt: serializer.fromJson<DateTime>(json['appliedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mode': serializer.toJson<String>(mode),
      'dataset': serializer.toJson<String>(dataset),
      'checksum': serializer.toJson<String>(checksum),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'records': serializer.toJson<int>(records),
      'sourceUpdatedAt': serializer.toJson<DateTime?>(sourceUpdatedAt),
      'appliedAt': serializer.toJson<DateTime>(appliedAt),
    };
  }

  DatasetState copyWith({
    String? mode,
    String? dataset,
    String? checksum,
    int? schemaVersion,
    int? records,
    Value<DateTime?> sourceUpdatedAt = const Value.absent(),
    DateTime? appliedAt,
  }) => DatasetState(
    mode: mode ?? this.mode,
    dataset: dataset ?? this.dataset,
    checksum: checksum ?? this.checksum,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    records: records ?? this.records,
    sourceUpdatedAt: sourceUpdatedAt.present
        ? sourceUpdatedAt.value
        : this.sourceUpdatedAt,
    appliedAt: appliedAt ?? this.appliedAt,
  );
  DatasetState copyWithCompanion(DatasetStatesCompanion data) {
    return DatasetState(
      mode: data.mode.present ? data.mode.value : this.mode,
      dataset: data.dataset.present ? data.dataset.value : this.dataset,
      checksum: data.checksum.present ? data.checksum.value : this.checksum,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      records: data.records.present ? data.records.value : this.records,
      sourceUpdatedAt: data.sourceUpdatedAt.present
          ? data.sourceUpdatedAt.value
          : this.sourceUpdatedAt,
      appliedAt: data.appliedAt.present ? data.appliedAt.value : this.appliedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DatasetState(')
          ..write('mode: $mode, ')
          ..write('dataset: $dataset, ')
          ..write('checksum: $checksum, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('records: $records, ')
          ..write('sourceUpdatedAt: $sourceUpdatedAt, ')
          ..write('appliedAt: $appliedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    mode,
    dataset,
    checksum,
    schemaVersion,
    records,
    sourceUpdatedAt,
    appliedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DatasetState &&
          other.mode == this.mode &&
          other.dataset == this.dataset &&
          other.checksum == this.checksum &&
          other.schemaVersion == this.schemaVersion &&
          other.records == this.records &&
          other.sourceUpdatedAt == this.sourceUpdatedAt &&
          other.appliedAt == this.appliedAt);
}

class DatasetStatesCompanion extends UpdateCompanion<DatasetState> {
  final Value<String> mode;
  final Value<String> dataset;
  final Value<String> checksum;
  final Value<int> schemaVersion;
  final Value<int> records;
  final Value<DateTime?> sourceUpdatedAt;
  final Value<DateTime> appliedAt;
  final Value<int> rowid;
  const DatasetStatesCompanion({
    this.mode = const Value.absent(),
    this.dataset = const Value.absent(),
    this.checksum = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.records = const Value.absent(),
    this.sourceUpdatedAt = const Value.absent(),
    this.appliedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DatasetStatesCompanion.insert({
    required String mode,
    required String dataset,
    required String checksum,
    required int schemaVersion,
    required int records,
    this.sourceUpdatedAt = const Value.absent(),
    required DateTime appliedAt,
    this.rowid = const Value.absent(),
  }) : mode = Value(mode),
       dataset = Value(dataset),
       checksum = Value(checksum),
       schemaVersion = Value(schemaVersion),
       records = Value(records),
       appliedAt = Value(appliedAt);
  static Insertable<DatasetState> custom({
    Expression<String>? mode,
    Expression<String>? dataset,
    Expression<String>? checksum,
    Expression<int>? schemaVersion,
    Expression<int>? records,
    Expression<DateTime>? sourceUpdatedAt,
    Expression<DateTime>? appliedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mode != null) 'mode': mode,
      if (dataset != null) 'dataset': dataset,
      if (checksum != null) 'checksum': checksum,
      if (schemaVersion != null) 'schemaVersion': schemaVersion,
      if (records != null) 'records': records,
      if (sourceUpdatedAt != null) 'sourceUpdatedAt': sourceUpdatedAt,
      if (appliedAt != null) 'appliedAt': appliedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DatasetStatesCompanion copyWith({
    Value<String>? mode,
    Value<String>? dataset,
    Value<String>? checksum,
    Value<int>? schemaVersion,
    Value<int>? records,
    Value<DateTime?>? sourceUpdatedAt,
    Value<DateTime>? appliedAt,
    Value<int>? rowid,
  }) {
    return DatasetStatesCompanion(
      mode: mode ?? this.mode,
      dataset: dataset ?? this.dataset,
      checksum: checksum ?? this.checksum,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      records: records ?? this.records,
      sourceUpdatedAt: sourceUpdatedAt ?? this.sourceUpdatedAt,
      appliedAt: appliedAt ?? this.appliedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (dataset.present) {
      map['dataset'] = Variable<String>(dataset.value);
    }
    if (checksum.present) {
      map['checksum'] = Variable<String>(checksum.value);
    }
    if (schemaVersion.present) {
      map['schemaVersion'] = Variable<int>(schemaVersion.value);
    }
    if (records.present) {
      map['records'] = Variable<int>(records.value);
    }
    if (sourceUpdatedAt.present) {
      map['sourceUpdatedAt'] = Variable<DateTime>(sourceUpdatedAt.value);
    }
    if (appliedAt.present) {
      map['appliedAt'] = Variable<DateTime>(appliedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DatasetStatesCompanion(')
          ..write('mode: $mode, ')
          ..write('dataset: $dataset, ')
          ..write('checksum: $checksum, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('records: $records, ')
          ..write('sourceUpdatedAt: $sourceUpdatedAt, ')
          ..write('appliedAt: $appliedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RemoteManifestsTable extends RemoteManifests
    with TableInfo<$RemoteManifestsTable, RemoteManifestRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RemoteManifestsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastModifiedMeta = const VerificationMeta(
    'lastModified',
  );
  @override
  late final GeneratedColumn<String> lastModified = GeneratedColumn<String>(
    'lastModified',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _manifestJsonMeta = const VerificationMeta(
    'manifestJson',
  );
  @override
  late final GeneratedColumn<String> manifestJson = GeneratedColumn<String>(
    'manifestJson',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _manifestGeneratedAtMeta =
      const VerificationMeta('manifestGeneratedAt');
  @override
  late final GeneratedColumn<String> manifestGeneratedAt =
      GeneratedColumn<String>(
        'manifestGeneratedAt',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastCheckedAtMeta = const VerificationMeta(
    'lastCheckedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastCheckedAt =
      GeneratedColumn<DateTime>(
        'lastCheckedAt',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _lastChangedAtMeta = const VerificationMeta(
    'lastChangedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastChangedAt =
      GeneratedColumn<DateTime>(
        'lastChangedAt',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'contentHash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    mode,
    etag,
    lastModified,
    manifestJson,
    manifestGeneratedAt,
    lastCheckedAt,
    lastChangedAt,
    contentHash,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'remoteManifest';
  @override
  VerificationContext validateIntegrity(
    Insertable<RemoteManifestRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    }
    if (data.containsKey('lastModified')) {
      context.handle(
        _lastModifiedMeta,
        lastModified.isAcceptableOrUnknown(
          data['lastModified']!,
          _lastModifiedMeta,
        ),
      );
    }
    if (data.containsKey('manifestJson')) {
      context.handle(
        _manifestJsonMeta,
        manifestJson.isAcceptableOrUnknown(
          data['manifestJson']!,
          _manifestJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manifestJsonMeta);
    }
    if (data.containsKey('manifestGeneratedAt')) {
      context.handle(
        _manifestGeneratedAtMeta,
        manifestGeneratedAt.isAcceptableOrUnknown(
          data['manifestGeneratedAt']!,
          _manifestGeneratedAtMeta,
        ),
      );
    }
    if (data.containsKey('lastCheckedAt')) {
      context.handle(
        _lastCheckedAtMeta,
        lastCheckedAt.isAcceptableOrUnknown(
          data['lastCheckedAt']!,
          _lastCheckedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastCheckedAtMeta);
    }
    if (data.containsKey('lastChangedAt')) {
      context.handle(
        _lastChangedAtMeta,
        lastChangedAt.isAcceptableOrUnknown(
          data['lastChangedAt']!,
          _lastChangedAtMeta,
        ),
      );
    }
    if (data.containsKey('contentHash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['contentHash']!,
          _contentHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mode};
  @override
  RemoteManifestRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RemoteManifestRecord(
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      ),
      lastModified: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lastModified'],
      ),
      manifestJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manifestJson'],
      )!,
      manifestGeneratedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manifestGeneratedAt'],
      ),
      lastCheckedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}lastCheckedAt'],
      )!,
      lastChangedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}lastChangedAt'],
      ),
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contentHash'],
      )!,
    );
  }

  @override
  $RemoteManifestsTable createAlias(String alias) {
    return $RemoteManifestsTable(attachedDatabase, alias);
  }
}

class RemoteManifestRecord extends DataClass
    implements Insertable<RemoteManifestRecord> {
  /// Game mode: `regular`, `pve` or `pvp-season`.
  final String mode;

  /// HTTP `ETag` from the last successful fetch, when the response had one.
  final String? etag;

  /// HTTP `Last-Modified` from the last successful fetch, when present.
  final String? lastModified;

  /// The raw manifest document exactly as received (a UTF-8 JSON object).
  final String manifestJson;

  /// The manifest's `generatedAt`, verbatim, as a diagnostic.
  final String? manifestGeneratedAt;

  /// When this client last asked the server about this mode's manifest.
  final DateTime lastCheckedAt;

  /// When the manifest body last changed, or `null` before the first change.
  final DateTime? lastChangedAt;

  /// Lowercase hex SHA-256 of the raw manifest bytes.
  final String contentHash;
  const RemoteManifestRecord({
    required this.mode,
    this.etag,
    this.lastModified,
    required this.manifestJson,
    this.manifestGeneratedAt,
    required this.lastCheckedAt,
    this.lastChangedAt,
    required this.contentHash,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['mode'] = Variable<String>(mode);
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    if (!nullToAbsent || lastModified != null) {
      map['lastModified'] = Variable<String>(lastModified);
    }
    map['manifestJson'] = Variable<String>(manifestJson);
    if (!nullToAbsent || manifestGeneratedAt != null) {
      map['manifestGeneratedAt'] = Variable<String>(manifestGeneratedAt);
    }
    map['lastCheckedAt'] = Variable<DateTime>(lastCheckedAt);
    if (!nullToAbsent || lastChangedAt != null) {
      map['lastChangedAt'] = Variable<DateTime>(lastChangedAt);
    }
    map['contentHash'] = Variable<String>(contentHash);
    return map;
  }

  RemoteManifestsCompanion toCompanion(bool nullToAbsent) {
    return RemoteManifestsCompanion(
      mode: Value(mode),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      lastModified: lastModified == null && nullToAbsent
          ? const Value.absent()
          : Value(lastModified),
      manifestJson: Value(manifestJson),
      manifestGeneratedAt: manifestGeneratedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(manifestGeneratedAt),
      lastCheckedAt: Value(lastCheckedAt),
      lastChangedAt: lastChangedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastChangedAt),
      contentHash: Value(contentHash),
    );
  }

  factory RemoteManifestRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RemoteManifestRecord(
      mode: serializer.fromJson<String>(json['mode']),
      etag: serializer.fromJson<String?>(json['etag']),
      lastModified: serializer.fromJson<String?>(json['lastModified']),
      manifestJson: serializer.fromJson<String>(json['manifestJson']),
      manifestGeneratedAt: serializer.fromJson<String?>(
        json['manifestGeneratedAt'],
      ),
      lastCheckedAt: serializer.fromJson<DateTime>(json['lastCheckedAt']),
      lastChangedAt: serializer.fromJson<DateTime?>(json['lastChangedAt']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mode': serializer.toJson<String>(mode),
      'etag': serializer.toJson<String?>(etag),
      'lastModified': serializer.toJson<String?>(lastModified),
      'manifestJson': serializer.toJson<String>(manifestJson),
      'manifestGeneratedAt': serializer.toJson<String?>(manifestGeneratedAt),
      'lastCheckedAt': serializer.toJson<DateTime>(lastCheckedAt),
      'lastChangedAt': serializer.toJson<DateTime?>(lastChangedAt),
      'contentHash': serializer.toJson<String>(contentHash),
    };
  }

  RemoteManifestRecord copyWith({
    String? mode,
    Value<String?> etag = const Value.absent(),
    Value<String?> lastModified = const Value.absent(),
    String? manifestJson,
    Value<String?> manifestGeneratedAt = const Value.absent(),
    DateTime? lastCheckedAt,
    Value<DateTime?> lastChangedAt = const Value.absent(),
    String? contentHash,
  }) => RemoteManifestRecord(
    mode: mode ?? this.mode,
    etag: etag.present ? etag.value : this.etag,
    lastModified: lastModified.present ? lastModified.value : this.lastModified,
    manifestJson: manifestJson ?? this.manifestJson,
    manifestGeneratedAt: manifestGeneratedAt.present
        ? manifestGeneratedAt.value
        : this.manifestGeneratedAt,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    lastChangedAt: lastChangedAt.present
        ? lastChangedAt.value
        : this.lastChangedAt,
    contentHash: contentHash ?? this.contentHash,
  );
  RemoteManifestRecord copyWithCompanion(RemoteManifestsCompanion data) {
    return RemoteManifestRecord(
      mode: data.mode.present ? data.mode.value : this.mode,
      etag: data.etag.present ? data.etag.value : this.etag,
      lastModified: data.lastModified.present
          ? data.lastModified.value
          : this.lastModified,
      manifestJson: data.manifestJson.present
          ? data.manifestJson.value
          : this.manifestJson,
      manifestGeneratedAt: data.manifestGeneratedAt.present
          ? data.manifestGeneratedAt.value
          : this.manifestGeneratedAt,
      lastCheckedAt: data.lastCheckedAt.present
          ? data.lastCheckedAt.value
          : this.lastCheckedAt,
      lastChangedAt: data.lastChangedAt.present
          ? data.lastChangedAt.value
          : this.lastChangedAt,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RemoteManifestRecord(')
          ..write('mode: $mode, ')
          ..write('etag: $etag, ')
          ..write('lastModified: $lastModified, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('manifestGeneratedAt: $manifestGeneratedAt, ')
          ..write('lastCheckedAt: $lastCheckedAt, ')
          ..write('lastChangedAt: $lastChangedAt, ')
          ..write('contentHash: $contentHash')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    mode,
    etag,
    lastModified,
    manifestJson,
    manifestGeneratedAt,
    lastCheckedAt,
    lastChangedAt,
    contentHash,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RemoteManifestRecord &&
          other.mode == this.mode &&
          other.etag == this.etag &&
          other.lastModified == this.lastModified &&
          other.manifestJson == this.manifestJson &&
          other.manifestGeneratedAt == this.manifestGeneratedAt &&
          other.lastCheckedAt == this.lastCheckedAt &&
          other.lastChangedAt == this.lastChangedAt &&
          other.contentHash == this.contentHash);
}

class RemoteManifestsCompanion extends UpdateCompanion<RemoteManifestRecord> {
  final Value<String> mode;
  final Value<String?> etag;
  final Value<String?> lastModified;
  final Value<String> manifestJson;
  final Value<String?> manifestGeneratedAt;
  final Value<DateTime> lastCheckedAt;
  final Value<DateTime?> lastChangedAt;
  final Value<String> contentHash;
  final Value<int> rowid;
  const RemoteManifestsCompanion({
    this.mode = const Value.absent(),
    this.etag = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.manifestJson = const Value.absent(),
    this.manifestGeneratedAt = const Value.absent(),
    this.lastCheckedAt = const Value.absent(),
    this.lastChangedAt = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RemoteManifestsCompanion.insert({
    required String mode,
    this.etag = const Value.absent(),
    this.lastModified = const Value.absent(),
    required String manifestJson,
    this.manifestGeneratedAt = const Value.absent(),
    required DateTime lastCheckedAt,
    this.lastChangedAt = const Value.absent(),
    required String contentHash,
    this.rowid = const Value.absent(),
  }) : mode = Value(mode),
       manifestJson = Value(manifestJson),
       lastCheckedAt = Value(lastCheckedAt),
       contentHash = Value(contentHash);
  static Insertable<RemoteManifestRecord> custom({
    Expression<String>? mode,
    Expression<String>? etag,
    Expression<String>? lastModified,
    Expression<String>? manifestJson,
    Expression<String>? manifestGeneratedAt,
    Expression<DateTime>? lastCheckedAt,
    Expression<DateTime>? lastChangedAt,
    Expression<String>? contentHash,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mode != null) 'mode': mode,
      if (etag != null) 'etag': etag,
      if (lastModified != null) 'lastModified': lastModified,
      if (manifestJson != null) 'manifestJson': manifestJson,
      if (manifestGeneratedAt != null)
        'manifestGeneratedAt': manifestGeneratedAt,
      if (lastCheckedAt != null) 'lastCheckedAt': lastCheckedAt,
      if (lastChangedAt != null) 'lastChangedAt': lastChangedAt,
      if (contentHash != null) 'contentHash': contentHash,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RemoteManifestsCompanion copyWith({
    Value<String>? mode,
    Value<String?>? etag,
    Value<String?>? lastModified,
    Value<String>? manifestJson,
    Value<String?>? manifestGeneratedAt,
    Value<DateTime>? lastCheckedAt,
    Value<DateTime?>? lastChangedAt,
    Value<String>? contentHash,
    Value<int>? rowid,
  }) {
    return RemoteManifestsCompanion(
      mode: mode ?? this.mode,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      manifestJson: manifestJson ?? this.manifestJson,
      manifestGeneratedAt: manifestGeneratedAt ?? this.manifestGeneratedAt,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      lastChangedAt: lastChangedAt ?? this.lastChangedAt,
      contentHash: contentHash ?? this.contentHash,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (lastModified.present) {
      map['lastModified'] = Variable<String>(lastModified.value);
    }
    if (manifestJson.present) {
      map['manifestJson'] = Variable<String>(manifestJson.value);
    }
    if (manifestGeneratedAt.present) {
      map['manifestGeneratedAt'] = Variable<String>(manifestGeneratedAt.value);
    }
    if (lastCheckedAt.present) {
      map['lastCheckedAt'] = Variable<DateTime>(lastCheckedAt.value);
    }
    if (lastChangedAt.present) {
      map['lastChangedAt'] = Variable<DateTime>(lastChangedAt.value);
    }
    if (contentHash.present) {
      map['contentHash'] = Variable<String>(contentHash.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RemoteManifestsCompanion(')
          ..write('mode: $mode, ')
          ..write('etag: $etag, ')
          ..write('lastModified: $lastModified, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('manifestGeneratedAt: $manifestGeneratedAt, ')
          ..write('lastCheckedAt: $lastCheckedAt, ')
          ..write('lastChangedAt: $lastChangedAt, ')
          ..write('contentHash: $contentHash, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ItemsTable extends Items with TableInfo<$ItemsTable, Item> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shortNameMeta = const VerificationMeta(
    'shortName',
  );
  @override
  late final GeneratedColumn<String> shortName = GeneratedColumn<String>(
    'shortName',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalizedNameMeta = const VerificationMeta(
    'normalizedName',
  );
  @override
  late final GeneratedColumn<String> normalizedName = GeneratedColumn<String>(
    'normalizedName',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weightMeta = const VerificationMeta('weight');
  @override
  late final GeneratedColumn<double> weight = GeneratedColumn<double>(
    'weight',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _basePriceMeta = const VerificationMeta(
    'basePrice',
  );
  @override
  late final GeneratedColumn<int> basePrice = GeneratedColumn<int>(
    'basePrice',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avg24hPriceMeta = const VerificationMeta(
    'avg24hPrice',
  );
  @override
  late final GeneratedColumn<int> avg24hPrice = GeneratedColumn<int>(
    'avg24hPrice',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastLowPriceMeta = const VerificationMeta(
    'lastLowPrice',
  );
  @override
  late final GeneratedColumn<int> lastLowPrice = GeneratedColumn<int>(
    'lastLowPrice',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _changeLast48hPercentMeta =
      const VerificationMeta('changeLast48hPercent');
  @override
  late final GeneratedColumn<double> changeLast48hPercent =
      GeneratedColumn<double>(
        'changeLast48hPercent',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _priceObservedAtMeta = const VerificationMeta(
    'priceObservedAt',
  );
  @override
  late final GeneratedColumn<DateTime> priceObservedAt =
      GeneratedColumn<DateTime>(
        'priceObservedAt',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _iconLinkMeta = const VerificationMeta(
    'iconLink',
  );
  @override
  late final GeneratedColumn<String> iconLink = GeneratedColumn<String>(
    'iconLink',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gridImageLinkMeta = const VerificationMeta(
    'gridImageLink',
  );
  @override
  late final GeneratedColumn<String> gridImageLink = GeneratedColumn<String>(
    'gridImageLink',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _minLevelForFleaMeta = const VerificationMeta(
    'minLevelForFlea',
  );
  @override
  late final GeneratedColumn<int> minLevelForFlea = GeneratedColumn<int>(
    'minLevelForFlea',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fleaEligibleMeta = const VerificationMeta(
    'fleaEligible',
  );
  @override
  late final GeneratedColumn<bool> fleaEligible = GeneratedColumn<bool>(
    'fleaEligible',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("fleaEligible" IN (0, 1))',
    ),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    shortName,
    normalizedName,
    weight,
    width,
    height,
    basePrice,
    avg24hPrice,
    lastLowPrice,
    changeLast48hPercent,
    priceObservedAt,
    iconLink,
    gridImageLink,
    minLevelForFlea,
    fleaEligible,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'items';
  @override
  VerificationContext validateIntegrity(
    Insertable<Item> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('shortName')) {
      context.handle(
        _shortNameMeta,
        shortName.isAcceptableOrUnknown(data['shortName']!, _shortNameMeta),
      );
    } else if (isInserting) {
      context.missing(_shortNameMeta);
    }
    if (data.containsKey('normalizedName')) {
      context.handle(
        _normalizedNameMeta,
        normalizedName.isAcceptableOrUnknown(
          data['normalizedName']!,
          _normalizedNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedNameMeta);
    }
    if (data.containsKey('weight')) {
      context.handle(
        _weightMeta,
        weight.isAcceptableOrUnknown(data['weight']!, _weightMeta),
      );
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('basePrice')) {
      context.handle(
        _basePriceMeta,
        basePrice.isAcceptableOrUnknown(data['basePrice']!, _basePriceMeta),
      );
    }
    if (data.containsKey('avg24hPrice')) {
      context.handle(
        _avg24hPriceMeta,
        avg24hPrice.isAcceptableOrUnknown(
          data['avg24hPrice']!,
          _avg24hPriceMeta,
        ),
      );
    }
    if (data.containsKey('lastLowPrice')) {
      context.handle(
        _lastLowPriceMeta,
        lastLowPrice.isAcceptableOrUnknown(
          data['lastLowPrice']!,
          _lastLowPriceMeta,
        ),
      );
    }
    if (data.containsKey('changeLast48hPercent')) {
      context.handle(
        _changeLast48hPercentMeta,
        changeLast48hPercent.isAcceptableOrUnknown(
          data['changeLast48hPercent']!,
          _changeLast48hPercentMeta,
        ),
      );
    }
    if (data.containsKey('priceObservedAt')) {
      context.handle(
        _priceObservedAtMeta,
        priceObservedAt.isAcceptableOrUnknown(
          data['priceObservedAt']!,
          _priceObservedAtMeta,
        ),
      );
    }
    if (data.containsKey('iconLink')) {
      context.handle(
        _iconLinkMeta,
        iconLink.isAcceptableOrUnknown(data['iconLink']!, _iconLinkMeta),
      );
    }
    if (data.containsKey('gridImageLink')) {
      context.handle(
        _gridImageLinkMeta,
        gridImageLink.isAcceptableOrUnknown(
          data['gridImageLink']!,
          _gridImageLinkMeta,
        ),
      );
    }
    if (data.containsKey('minLevelForFlea')) {
      context.handle(
        _minLevelForFleaMeta,
        minLevelForFlea.isAcceptableOrUnknown(
          data['minLevelForFlea']!,
          _minLevelForFleaMeta,
        ),
      );
    }
    if (data.containsKey('fleaEligible')) {
      context.handle(
        _fleaEligibleMeta,
        fleaEligible.isAcceptableOrUnknown(
          data['fleaEligible']!,
          _fleaEligibleMeta,
        ),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Item map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Item(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      shortName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shortName'],
      )!,
      normalizedName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalizedName'],
      )!,
      weight: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight'],
      ),
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      basePrice: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}basePrice'],
      ),
      avg24hPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}avg24hPrice'],
      ),
      lastLowPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lastLowPrice'],
      ),
      changeLast48hPercent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}changeLast48hPercent'],
      ),
      priceObservedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}priceObservedAt'],
      ),
      iconLink: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}iconLink'],
      ),
      gridImageLink: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gridImageLink'],
      ),
      minLevelForFlea: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minLevelForFlea'],
      ),
      fleaEligible: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}fleaEligible'],
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $ItemsTable createAlias(String alias) {
    return $ItemsTable(attachedDatabase, alias);
  }
}

class Item extends DataClass implements Insertable<Item> {
  /// Upstream item id (`items[].id`).
  final String id;

  /// Display name, localized by the pipeline.
  final String name;

  /// Short display name (`M4A1`).
  final String shortName;

  /// Diacritic-free, lower-case search key from the bundle.
  final String normalizedName;

  /// Weight in kilograms.
  final double? weight;

  /// Grid width in slots.
  final int? width;

  /// Grid height in slots.
  final int? height;

  /// Trader-independent base price in roubles.
  final int? basePrice;

  /// Flea-market 24 h average, `price.avg24h`.
  final int? avg24hPrice;

  /// Latest flea-market low, `price.lastLow`.
  final int? lastLowPrice;

  /// 48 h flea price change as a percentage, `price.change48hPercent`.
  final double? changeLast48hPercent;

  /// When the newest price snapshot was observed, `price.observedAt`.
  ///
  /// This is the price's own observation time, not the time the dataset was
  /// applied (`datasetState.appliedAt`): a bundle can be reloaded without
  /// upstream observing a new price. `null` means the bundle carried no
  /// observation, which the freshness policy reports as unknown.
  final DateTime? priceObservedAt;

  /// Icon URL.
  final String? iconLink;

  /// Grid image URL.
  final String? gridImageLink;

  /// Minimum player level the flea market requires for this item.
  ///
  /// The bundle's `minLevelForFlea`; `0` means no level requirement. Nullable
  /// because a row migrated from schema v4 has no value until the next `items`
  /// bundle is applied. Eligibility itself is [fleaEligible], not this number:
  /// a level-gated item is still sellable on the flea market.
  final int? minLevelForFlea;

  /// Whether the item may appear on the flea market (`types` excludes
  /// `noFlea`).
  ///
  /// Nullable for the same reason as [minLevelForFlea]: a row migrated from
  /// schema v4 is "unknown" rather than silently guessed as eligible. Catalog
  /// filters only match rows with an explicit `true`/`false`.
  final bool? fleaEligible;

  /// The complete bundle record as canonical JSON.
  final String payload;
  const Item({
    required this.id,
    required this.name,
    required this.shortName,
    required this.normalizedName,
    this.weight,
    this.width,
    this.height,
    this.basePrice,
    this.avg24hPrice,
    this.lastLowPrice,
    this.changeLast48hPercent,
    this.priceObservedAt,
    this.iconLink,
    this.gridImageLink,
    this.minLevelForFlea,
    this.fleaEligible,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['shortName'] = Variable<String>(shortName);
    map['normalizedName'] = Variable<String>(normalizedName);
    if (!nullToAbsent || weight != null) {
      map['weight'] = Variable<double>(weight);
    }
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    if (!nullToAbsent || basePrice != null) {
      map['basePrice'] = Variable<int>(basePrice);
    }
    if (!nullToAbsent || avg24hPrice != null) {
      map['avg24hPrice'] = Variable<int>(avg24hPrice);
    }
    if (!nullToAbsent || lastLowPrice != null) {
      map['lastLowPrice'] = Variable<int>(lastLowPrice);
    }
    if (!nullToAbsent || changeLast48hPercent != null) {
      map['changeLast48hPercent'] = Variable<double>(changeLast48hPercent);
    }
    if (!nullToAbsent || priceObservedAt != null) {
      map['priceObservedAt'] = Variable<DateTime>(priceObservedAt);
    }
    if (!nullToAbsent || iconLink != null) {
      map['iconLink'] = Variable<String>(iconLink);
    }
    if (!nullToAbsent || gridImageLink != null) {
      map['gridImageLink'] = Variable<String>(gridImageLink);
    }
    if (!nullToAbsent || minLevelForFlea != null) {
      map['minLevelForFlea'] = Variable<int>(minLevelForFlea);
    }
    if (!nullToAbsent || fleaEligible != null) {
      map['fleaEligible'] = Variable<bool>(fleaEligible);
    }
    map['payload'] = Variable<String>(payload);
    return map;
  }

  ItemsCompanion toCompanion(bool nullToAbsent) {
    return ItemsCompanion(
      id: Value(id),
      name: Value(name),
      shortName: Value(shortName),
      normalizedName: Value(normalizedName),
      weight: weight == null && nullToAbsent
          ? const Value.absent()
          : Value(weight),
      width: width == null && nullToAbsent
          ? const Value.absent()
          : Value(width),
      height: height == null && nullToAbsent
          ? const Value.absent()
          : Value(height),
      basePrice: basePrice == null && nullToAbsent
          ? const Value.absent()
          : Value(basePrice),
      avg24hPrice: avg24hPrice == null && nullToAbsent
          ? const Value.absent()
          : Value(avg24hPrice),
      lastLowPrice: lastLowPrice == null && nullToAbsent
          ? const Value.absent()
          : Value(lastLowPrice),
      changeLast48hPercent: changeLast48hPercent == null && nullToAbsent
          ? const Value.absent()
          : Value(changeLast48hPercent),
      priceObservedAt: priceObservedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(priceObservedAt),
      iconLink: iconLink == null && nullToAbsent
          ? const Value.absent()
          : Value(iconLink),
      gridImageLink: gridImageLink == null && nullToAbsent
          ? const Value.absent()
          : Value(gridImageLink),
      minLevelForFlea: minLevelForFlea == null && nullToAbsent
          ? const Value.absent()
          : Value(minLevelForFlea),
      fleaEligible: fleaEligible == null && nullToAbsent
          ? const Value.absent()
          : Value(fleaEligible),
      payload: Value(payload),
    );
  }

  factory Item.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Item(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      shortName: serializer.fromJson<String>(json['shortName']),
      normalizedName: serializer.fromJson<String>(json['normalizedName']),
      weight: serializer.fromJson<double?>(json['weight']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      basePrice: serializer.fromJson<int?>(json['basePrice']),
      avg24hPrice: serializer.fromJson<int?>(json['avg24hPrice']),
      lastLowPrice: serializer.fromJson<int?>(json['lastLowPrice']),
      changeLast48hPercent: serializer.fromJson<double?>(
        json['changeLast48hPercent'],
      ),
      priceObservedAt: serializer.fromJson<DateTime?>(json['priceObservedAt']),
      iconLink: serializer.fromJson<String?>(json['iconLink']),
      gridImageLink: serializer.fromJson<String?>(json['gridImageLink']),
      minLevelForFlea: serializer.fromJson<int?>(json['minLevelForFlea']),
      fleaEligible: serializer.fromJson<bool?>(json['fleaEligible']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'shortName': serializer.toJson<String>(shortName),
      'normalizedName': serializer.toJson<String>(normalizedName),
      'weight': serializer.toJson<double?>(weight),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'basePrice': serializer.toJson<int?>(basePrice),
      'avg24hPrice': serializer.toJson<int?>(avg24hPrice),
      'lastLowPrice': serializer.toJson<int?>(lastLowPrice),
      'changeLast48hPercent': serializer.toJson<double?>(changeLast48hPercent),
      'priceObservedAt': serializer.toJson<DateTime?>(priceObservedAt),
      'iconLink': serializer.toJson<String?>(iconLink),
      'gridImageLink': serializer.toJson<String?>(gridImageLink),
      'minLevelForFlea': serializer.toJson<int?>(minLevelForFlea),
      'fleaEligible': serializer.toJson<bool?>(fleaEligible),
      'payload': serializer.toJson<String>(payload),
    };
  }

  Item copyWith({
    String? id,
    String? name,
    String? shortName,
    String? normalizedName,
    Value<double?> weight = const Value.absent(),
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    Value<int?> basePrice = const Value.absent(),
    Value<int?> avg24hPrice = const Value.absent(),
    Value<int?> lastLowPrice = const Value.absent(),
    Value<double?> changeLast48hPercent = const Value.absent(),
    Value<DateTime?> priceObservedAt = const Value.absent(),
    Value<String?> iconLink = const Value.absent(),
    Value<String?> gridImageLink = const Value.absent(),
    Value<int?> minLevelForFlea = const Value.absent(),
    Value<bool?> fleaEligible = const Value.absent(),
    String? payload,
  }) => Item(
    id: id ?? this.id,
    name: name ?? this.name,
    shortName: shortName ?? this.shortName,
    normalizedName: normalizedName ?? this.normalizedName,
    weight: weight.present ? weight.value : this.weight,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    basePrice: basePrice.present ? basePrice.value : this.basePrice,
    avg24hPrice: avg24hPrice.present ? avg24hPrice.value : this.avg24hPrice,
    lastLowPrice: lastLowPrice.present ? lastLowPrice.value : this.lastLowPrice,
    changeLast48hPercent: changeLast48hPercent.present
        ? changeLast48hPercent.value
        : this.changeLast48hPercent,
    priceObservedAt: priceObservedAt.present
        ? priceObservedAt.value
        : this.priceObservedAt,
    iconLink: iconLink.present ? iconLink.value : this.iconLink,
    gridImageLink: gridImageLink.present
        ? gridImageLink.value
        : this.gridImageLink,
    minLevelForFlea: minLevelForFlea.present
        ? minLevelForFlea.value
        : this.minLevelForFlea,
    fleaEligible: fleaEligible.present ? fleaEligible.value : this.fleaEligible,
    payload: payload ?? this.payload,
  );
  Item copyWithCompanion(ItemsCompanion data) {
    return Item(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      shortName: data.shortName.present ? data.shortName.value : this.shortName,
      normalizedName: data.normalizedName.present
          ? data.normalizedName.value
          : this.normalizedName,
      weight: data.weight.present ? data.weight.value : this.weight,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      basePrice: data.basePrice.present ? data.basePrice.value : this.basePrice,
      avg24hPrice: data.avg24hPrice.present
          ? data.avg24hPrice.value
          : this.avg24hPrice,
      lastLowPrice: data.lastLowPrice.present
          ? data.lastLowPrice.value
          : this.lastLowPrice,
      changeLast48hPercent: data.changeLast48hPercent.present
          ? data.changeLast48hPercent.value
          : this.changeLast48hPercent,
      priceObservedAt: data.priceObservedAt.present
          ? data.priceObservedAt.value
          : this.priceObservedAt,
      iconLink: data.iconLink.present ? data.iconLink.value : this.iconLink,
      gridImageLink: data.gridImageLink.present
          ? data.gridImageLink.value
          : this.gridImageLink,
      minLevelForFlea: data.minLevelForFlea.present
          ? data.minLevelForFlea.value
          : this.minLevelForFlea,
      fleaEligible: data.fleaEligible.present
          ? data.fleaEligible.value
          : this.fleaEligible,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Item(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('shortName: $shortName, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('weight: $weight, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('basePrice: $basePrice, ')
          ..write('avg24hPrice: $avg24hPrice, ')
          ..write('lastLowPrice: $lastLowPrice, ')
          ..write('changeLast48hPercent: $changeLast48hPercent, ')
          ..write('priceObservedAt: $priceObservedAt, ')
          ..write('iconLink: $iconLink, ')
          ..write('gridImageLink: $gridImageLink, ')
          ..write('minLevelForFlea: $minLevelForFlea, ')
          ..write('fleaEligible: $fleaEligible, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    shortName,
    normalizedName,
    weight,
    width,
    height,
    basePrice,
    avg24hPrice,
    lastLowPrice,
    changeLast48hPercent,
    priceObservedAt,
    iconLink,
    gridImageLink,
    minLevelForFlea,
    fleaEligible,
    payload,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Item &&
          other.id == this.id &&
          other.name == this.name &&
          other.shortName == this.shortName &&
          other.normalizedName == this.normalizedName &&
          other.weight == this.weight &&
          other.width == this.width &&
          other.height == this.height &&
          other.basePrice == this.basePrice &&
          other.avg24hPrice == this.avg24hPrice &&
          other.lastLowPrice == this.lastLowPrice &&
          other.changeLast48hPercent == this.changeLast48hPercent &&
          other.priceObservedAt == this.priceObservedAt &&
          other.iconLink == this.iconLink &&
          other.gridImageLink == this.gridImageLink &&
          other.minLevelForFlea == this.minLevelForFlea &&
          other.fleaEligible == this.fleaEligible &&
          other.payload == this.payload);
}

class ItemsCompanion extends UpdateCompanion<Item> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> shortName;
  final Value<String> normalizedName;
  final Value<double?> weight;
  final Value<int?> width;
  final Value<int?> height;
  final Value<int?> basePrice;
  final Value<int?> avg24hPrice;
  final Value<int?> lastLowPrice;
  final Value<double?> changeLast48hPercent;
  final Value<DateTime?> priceObservedAt;
  final Value<String?> iconLink;
  final Value<String?> gridImageLink;
  final Value<int?> minLevelForFlea;
  final Value<bool?> fleaEligible;
  final Value<String> payload;
  final Value<int> rowid;
  const ItemsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.shortName = const Value.absent(),
    this.normalizedName = const Value.absent(),
    this.weight = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.basePrice = const Value.absent(),
    this.avg24hPrice = const Value.absent(),
    this.lastLowPrice = const Value.absent(),
    this.changeLast48hPercent = const Value.absent(),
    this.priceObservedAt = const Value.absent(),
    this.iconLink = const Value.absent(),
    this.gridImageLink = const Value.absent(),
    this.minLevelForFlea = const Value.absent(),
    this.fleaEligible = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ItemsCompanion.insert({
    required String id,
    required String name,
    required String shortName,
    required String normalizedName,
    this.weight = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.basePrice = const Value.absent(),
    this.avg24hPrice = const Value.absent(),
    this.lastLowPrice = const Value.absent(),
    this.changeLast48hPercent = const Value.absent(),
    this.priceObservedAt = const Value.absent(),
    this.iconLink = const Value.absent(),
    this.gridImageLink = const Value.absent(),
    this.minLevelForFlea = const Value.absent(),
    this.fleaEligible = const Value.absent(),
    required String payload,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       shortName = Value(shortName),
       normalizedName = Value(normalizedName),
       payload = Value(payload);
  static Insertable<Item> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? shortName,
    Expression<String>? normalizedName,
    Expression<double>? weight,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? basePrice,
    Expression<int>? avg24hPrice,
    Expression<int>? lastLowPrice,
    Expression<double>? changeLast48hPercent,
    Expression<DateTime>? priceObservedAt,
    Expression<String>? iconLink,
    Expression<String>? gridImageLink,
    Expression<int>? minLevelForFlea,
    Expression<bool>? fleaEligible,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (shortName != null) 'shortName': shortName,
      if (normalizedName != null) 'normalizedName': normalizedName,
      if (weight != null) 'weight': weight,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (basePrice != null) 'basePrice': basePrice,
      if (avg24hPrice != null) 'avg24hPrice': avg24hPrice,
      if (lastLowPrice != null) 'lastLowPrice': lastLowPrice,
      if (changeLast48hPercent != null)
        'changeLast48hPercent': changeLast48hPercent,
      if (priceObservedAt != null) 'priceObservedAt': priceObservedAt,
      if (iconLink != null) 'iconLink': iconLink,
      if (gridImageLink != null) 'gridImageLink': gridImageLink,
      if (minLevelForFlea != null) 'minLevelForFlea': minLevelForFlea,
      if (fleaEligible != null) 'fleaEligible': fleaEligible,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? shortName,
    Value<String>? normalizedName,
    Value<double?>? weight,
    Value<int?>? width,
    Value<int?>? height,
    Value<int?>? basePrice,
    Value<int?>? avg24hPrice,
    Value<int?>? lastLowPrice,
    Value<double?>? changeLast48hPercent,
    Value<DateTime?>? priceObservedAt,
    Value<String?>? iconLink,
    Value<String?>? gridImageLink,
    Value<int?>? minLevelForFlea,
    Value<bool?>? fleaEligible,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return ItemsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      shortName: shortName ?? this.shortName,
      normalizedName: normalizedName ?? this.normalizedName,
      weight: weight ?? this.weight,
      width: width ?? this.width,
      height: height ?? this.height,
      basePrice: basePrice ?? this.basePrice,
      avg24hPrice: avg24hPrice ?? this.avg24hPrice,
      lastLowPrice: lastLowPrice ?? this.lastLowPrice,
      changeLast48hPercent: changeLast48hPercent ?? this.changeLast48hPercent,
      priceObservedAt: priceObservedAt ?? this.priceObservedAt,
      iconLink: iconLink ?? this.iconLink,
      gridImageLink: gridImageLink ?? this.gridImageLink,
      minLevelForFlea: minLevelForFlea ?? this.minLevelForFlea,
      fleaEligible: fleaEligible ?? this.fleaEligible,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (shortName.present) {
      map['shortName'] = Variable<String>(shortName.value);
    }
    if (normalizedName.present) {
      map['normalizedName'] = Variable<String>(normalizedName.value);
    }
    if (weight.present) {
      map['weight'] = Variable<double>(weight.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (basePrice.present) {
      map['basePrice'] = Variable<int>(basePrice.value);
    }
    if (avg24hPrice.present) {
      map['avg24hPrice'] = Variable<int>(avg24hPrice.value);
    }
    if (lastLowPrice.present) {
      map['lastLowPrice'] = Variable<int>(lastLowPrice.value);
    }
    if (changeLast48hPercent.present) {
      map['changeLast48hPercent'] = Variable<double>(
        changeLast48hPercent.value,
      );
    }
    if (priceObservedAt.present) {
      map['priceObservedAt'] = Variable<DateTime>(priceObservedAt.value);
    }
    if (iconLink.present) {
      map['iconLink'] = Variable<String>(iconLink.value);
    }
    if (gridImageLink.present) {
      map['gridImageLink'] = Variable<String>(gridImageLink.value);
    }
    if (minLevelForFlea.present) {
      map['minLevelForFlea'] = Variable<int>(minLevelForFlea.value);
    }
    if (fleaEligible.present) {
      map['fleaEligible'] = Variable<bool>(fleaEligible.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ItemsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('shortName: $shortName, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('weight: $weight, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('basePrice: $basePrice, ')
          ..write('avg24hPrice: $avg24hPrice, ')
          ..write('lastLowPrice: $lastLowPrice, ')
          ..write('changeLast48hPercent: $changeLast48hPercent, ')
          ..write('priceObservedAt: $priceObservedAt, ')
          ..write('iconLink: $iconLink, ')
          ..write('gridImageLink: $gridImageLink, ')
          ..write('minLevelForFlea: $minLevelForFlea, ')
          ..write('fleaEligible: $fleaEligible, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ItemTypesTable extends ItemTypes
    with TableInfo<$ItemTypesTable, ItemType> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ItemTypesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'itemId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [itemId, type];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'itemTypes';
  @override
  VerificationContext validateIntegrity(
    Insertable<ItemType> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('itemId')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['itemId']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {itemId, type};
  @override
  ItemType map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ItemType(
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}itemId'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
    );
  }

  @override
  $ItemTypesTable createAlias(String alias) {
    return $ItemTypesTable(attachedDatabase, alias);
  }
}

class ItemType extends DataClass implements Insertable<ItemType> {
  /// Owning item.
  final String itemId;

  /// Bundle `types[]` value.
  final String type;
  const ItemType({required this.itemId, required this.type});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['itemId'] = Variable<String>(itemId);
    map['type'] = Variable<String>(type);
    return map;
  }

  ItemTypesCompanion toCompanion(bool nullToAbsent) {
    return ItemTypesCompanion(itemId: Value(itemId), type: Value(type));
  }

  factory ItemType.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ItemType(
      itemId: serializer.fromJson<String>(json['itemId']),
      type: serializer.fromJson<String>(json['type']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'itemId': serializer.toJson<String>(itemId),
      'type': serializer.toJson<String>(type),
    };
  }

  ItemType copyWith({String? itemId, String? type}) =>
      ItemType(itemId: itemId ?? this.itemId, type: type ?? this.type);
  ItemType copyWithCompanion(ItemTypesCompanion data) {
    return ItemType(
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      type: data.type.present ? data.type.value : this.type,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ItemType(')
          ..write('itemId: $itemId, ')
          ..write('type: $type')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(itemId, type);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ItemType &&
          other.itemId == this.itemId &&
          other.type == this.type);
}

class ItemTypesCompanion extends UpdateCompanion<ItemType> {
  final Value<String> itemId;
  final Value<String> type;
  final Value<int> rowid;
  const ItemTypesCompanion({
    this.itemId = const Value.absent(),
    this.type = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ItemTypesCompanion.insert({
    required String itemId,
    required String type,
    this.rowid = const Value.absent(),
  }) : itemId = Value(itemId),
       type = Value(type);
  static Insertable<ItemType> custom({
    Expression<String>? itemId,
    Expression<String>? type,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (itemId != null) 'itemId': itemId,
      if (type != null) 'type': type,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ItemTypesCompanion copyWith({
    Value<String>? itemId,
    Value<String>? type,
    Value<int>? rowid,
  }) {
    return ItemTypesCompanion(
      itemId: itemId ?? this.itemId,
      type: type ?? this.type,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (itemId.present) {
      map['itemId'] = Variable<String>(itemId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ItemTypesCompanion(')
          ..write('itemId: $itemId, ')
          ..write('type: $type, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ItemCategoriesTable extends ItemCategories
    with TableInfo<$ItemCategoriesTable, ItemCategory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ItemCategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'itemId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'categoryId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryKindMeta = const VerificationMeta(
    'categoryKind',
  );
  @override
  late final GeneratedColumn<String> categoryKind = GeneratedColumn<String>(
    'categoryKind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [itemId, categoryId, categoryKind];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'itemCategories';
  @override
  VerificationContext validateIntegrity(
    Insertable<ItemCategory> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('itemId')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['itemId']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('categoryId')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['categoryId']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('categoryKind')) {
      context.handle(
        _categoryKindMeta,
        categoryKind.isAcceptableOrUnknown(
          data['categoryKind']!,
          _categoryKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_categoryKindMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {itemId, categoryId, categoryKind};
  @override
  ItemCategory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ItemCategory(
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}itemId'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}categoryId'],
      )!,
      categoryKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}categoryKind'],
      )!,
    );
  }

  @override
  $ItemCategoriesTable createAlias(String alias) {
    return $ItemCategoriesTable(attachedDatabase, alias);
  }
}

class ItemCategory extends DataClass implements Insertable<ItemCategory> {
  /// Owning item.
  final String itemId;

  /// Category id from the bundle's `categoryIds` or `handbookCategoryIds`.
  final String categoryId;

  /// `item` for `categoryIds`, `handbook` for `handbookCategoryIds`.
  final String categoryKind;
  const ItemCategory({
    required this.itemId,
    required this.categoryId,
    required this.categoryKind,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['itemId'] = Variable<String>(itemId);
    map['categoryId'] = Variable<String>(categoryId);
    map['categoryKind'] = Variable<String>(categoryKind);
    return map;
  }

  ItemCategoriesCompanion toCompanion(bool nullToAbsent) {
    return ItemCategoriesCompanion(
      itemId: Value(itemId),
      categoryId: Value(categoryId),
      categoryKind: Value(categoryKind),
    );
  }

  factory ItemCategory.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ItemCategory(
      itemId: serializer.fromJson<String>(json['itemId']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      categoryKind: serializer.fromJson<String>(json['categoryKind']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'itemId': serializer.toJson<String>(itemId),
      'categoryId': serializer.toJson<String>(categoryId),
      'categoryKind': serializer.toJson<String>(categoryKind),
    };
  }

  ItemCategory copyWith({
    String? itemId,
    String? categoryId,
    String? categoryKind,
  }) => ItemCategory(
    itemId: itemId ?? this.itemId,
    categoryId: categoryId ?? this.categoryId,
    categoryKind: categoryKind ?? this.categoryKind,
  );
  ItemCategory copyWithCompanion(ItemCategoriesCompanion data) {
    return ItemCategory(
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      categoryKind: data.categoryKind.present
          ? data.categoryKind.value
          : this.categoryKind,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ItemCategory(')
          ..write('itemId: $itemId, ')
          ..write('categoryId: $categoryId, ')
          ..write('categoryKind: $categoryKind')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(itemId, categoryId, categoryKind);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ItemCategory &&
          other.itemId == this.itemId &&
          other.categoryId == this.categoryId &&
          other.categoryKind == this.categoryKind);
}

class ItemCategoriesCompanion extends UpdateCompanion<ItemCategory> {
  final Value<String> itemId;
  final Value<String> categoryId;
  final Value<String> categoryKind;
  final Value<int> rowid;
  const ItemCategoriesCompanion({
    this.itemId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.categoryKind = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ItemCategoriesCompanion.insert({
    required String itemId,
    required String categoryId,
    required String categoryKind,
    this.rowid = const Value.absent(),
  }) : itemId = Value(itemId),
       categoryId = Value(categoryId),
       categoryKind = Value(categoryKind);
  static Insertable<ItemCategory> custom({
    Expression<String>? itemId,
    Expression<String>? categoryId,
    Expression<String>? categoryKind,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (itemId != null) 'itemId': itemId,
      if (categoryId != null) 'categoryId': categoryId,
      if (categoryKind != null) 'categoryKind': categoryKind,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ItemCategoriesCompanion copyWith({
    Value<String>? itemId,
    Value<String>? categoryId,
    Value<String>? categoryKind,
    Value<int>? rowid,
  }) {
    return ItemCategoriesCompanion(
      itemId: itemId ?? this.itemId,
      categoryId: categoryId ?? this.categoryId,
      categoryKind: categoryKind ?? this.categoryKind,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (itemId.present) {
      map['itemId'] = Variable<String>(itemId.value);
    }
    if (categoryId.present) {
      map['categoryId'] = Variable<String>(categoryId.value);
    }
    if (categoryKind.present) {
      map['categoryKind'] = Variable<String>(categoryKind.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ItemCategoriesCompanion(')
          ..write('itemId: $itemId, ')
          ..write('categoryId: $categoryId, ')
          ..write('categoryKind: $categoryKind, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TasksTable extends Tasks with TableInfo<$TasksTable, Task> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _traderIdMeta = const VerificationMeta(
    'traderId',
  );
  @override
  late final GeneratedColumn<String> traderId = GeneratedColumn<String>(
    'traderId',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mapIdMeta = const VerificationMeta('mapId');
  @override
  late final GeneratedColumn<String> mapId = GeneratedColumn<String>(
    'mapId',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _minPlayerLevelMeta = const VerificationMeta(
    'minPlayerLevel',
  );
  @override
  late final GeneratedColumn<int> minPlayerLevel = GeneratedColumn<int>(
    'minPlayerLevel',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _experienceMeta = const VerificationMeta(
    'experience',
  );
  @override
  late final GeneratedColumn<int> experience = GeneratedColumn<int>(
    'experience',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kappaRequiredMeta = const VerificationMeta(
    'kappaRequired',
  );
  @override
  late final GeneratedColumn<bool> kappaRequired = GeneratedColumn<bool>(
    'kappaRequired',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("kappaRequired" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    traderId,
    mapId,
    minPlayerLevel,
    experience,
    kappaRequired,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Task> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('traderId')) {
      context.handle(
        _traderIdMeta,
        traderId.isAcceptableOrUnknown(data['traderId']!, _traderIdMeta),
      );
    }
    if (data.containsKey('mapId')) {
      context.handle(
        _mapIdMeta,
        mapId.isAcceptableOrUnknown(data['mapId']!, _mapIdMeta),
      );
    }
    if (data.containsKey('minPlayerLevel')) {
      context.handle(
        _minPlayerLevelMeta,
        minPlayerLevel.isAcceptableOrUnknown(
          data['minPlayerLevel']!,
          _minPlayerLevelMeta,
        ),
      );
    }
    if (data.containsKey('experience')) {
      context.handle(
        _experienceMeta,
        experience.isAcceptableOrUnknown(data['experience']!, _experienceMeta),
      );
    }
    if (data.containsKey('kappaRequired')) {
      context.handle(
        _kappaRequiredMeta,
        kappaRequired.isAcceptableOrUnknown(
          data['kappaRequired']!,
          _kappaRequiredMeta,
        ),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Task map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Task(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      traderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}traderId'],
      ),
      mapId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mapId'],
      ),
      minPlayerLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minPlayerLevel'],
      ),
      experience: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}experience'],
      ),
      kappaRequired: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}kappaRequired'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }
}

class Task extends DataClass implements Insertable<Task> {
  /// Upstream task id.
  final String id;

  /// Localized quest name.
  final String name;

  /// Trader that gives the quest.
  final String? traderId;

  /// Primary map of the quest, when upstream provides one.
  final String? mapId;

  /// Minimum player level required to accept the quest.
  final int? minPlayerLevel;

  /// Experience reward. Upstream may send `null`.
  final int? experience;

  /// Whether the quest counts towards the Kappa container.
  final bool kappaRequired;

  /// The complete bundle record as canonical JSON.
  final String payload;
  const Task({
    required this.id,
    required this.name,
    this.traderId,
    this.mapId,
    this.minPlayerLevel,
    this.experience,
    required this.kappaRequired,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || traderId != null) {
      map['traderId'] = Variable<String>(traderId);
    }
    if (!nullToAbsent || mapId != null) {
      map['mapId'] = Variable<String>(mapId);
    }
    if (!nullToAbsent || minPlayerLevel != null) {
      map['minPlayerLevel'] = Variable<int>(minPlayerLevel);
    }
    if (!nullToAbsent || experience != null) {
      map['experience'] = Variable<int>(experience);
    }
    map['kappaRequired'] = Variable<bool>(kappaRequired);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      name: Value(name),
      traderId: traderId == null && nullToAbsent
          ? const Value.absent()
          : Value(traderId),
      mapId: mapId == null && nullToAbsent
          ? const Value.absent()
          : Value(mapId),
      minPlayerLevel: minPlayerLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(minPlayerLevel),
      experience: experience == null && nullToAbsent
          ? const Value.absent()
          : Value(experience),
      kappaRequired: Value(kappaRequired),
      payload: Value(payload),
    );
  }

  factory Task.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Task(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      traderId: serializer.fromJson<String?>(json['traderId']),
      mapId: serializer.fromJson<String?>(json['mapId']),
      minPlayerLevel: serializer.fromJson<int?>(json['minPlayerLevel']),
      experience: serializer.fromJson<int?>(json['experience']),
      kappaRequired: serializer.fromJson<bool>(json['kappaRequired']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'traderId': serializer.toJson<String?>(traderId),
      'mapId': serializer.toJson<String?>(mapId),
      'minPlayerLevel': serializer.toJson<int?>(minPlayerLevel),
      'experience': serializer.toJson<int?>(experience),
      'kappaRequired': serializer.toJson<bool>(kappaRequired),
      'payload': serializer.toJson<String>(payload),
    };
  }

  Task copyWith({
    String? id,
    String? name,
    Value<String?> traderId = const Value.absent(),
    Value<String?> mapId = const Value.absent(),
    Value<int?> minPlayerLevel = const Value.absent(),
    Value<int?> experience = const Value.absent(),
    bool? kappaRequired,
    String? payload,
  }) => Task(
    id: id ?? this.id,
    name: name ?? this.name,
    traderId: traderId.present ? traderId.value : this.traderId,
    mapId: mapId.present ? mapId.value : this.mapId,
    minPlayerLevel: minPlayerLevel.present
        ? minPlayerLevel.value
        : this.minPlayerLevel,
    experience: experience.present ? experience.value : this.experience,
    kappaRequired: kappaRequired ?? this.kappaRequired,
    payload: payload ?? this.payload,
  );
  Task copyWithCompanion(TasksCompanion data) {
    return Task(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      traderId: data.traderId.present ? data.traderId.value : this.traderId,
      mapId: data.mapId.present ? data.mapId.value : this.mapId,
      minPlayerLevel: data.minPlayerLevel.present
          ? data.minPlayerLevel.value
          : this.minPlayerLevel,
      experience: data.experience.present
          ? data.experience.value
          : this.experience,
      kappaRequired: data.kappaRequired.present
          ? data.kappaRequired.value
          : this.kappaRequired,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Task(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('traderId: $traderId, ')
          ..write('mapId: $mapId, ')
          ..write('minPlayerLevel: $minPlayerLevel, ')
          ..write('experience: $experience, ')
          ..write('kappaRequired: $kappaRequired, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    traderId,
    mapId,
    minPlayerLevel,
    experience,
    kappaRequired,
    payload,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Task &&
          other.id == this.id &&
          other.name == this.name &&
          other.traderId == this.traderId &&
          other.mapId == this.mapId &&
          other.minPlayerLevel == this.minPlayerLevel &&
          other.experience == this.experience &&
          other.kappaRequired == this.kappaRequired &&
          other.payload == this.payload);
}

class TasksCompanion extends UpdateCompanion<Task> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> traderId;
  final Value<String?> mapId;
  final Value<int?> minPlayerLevel;
  final Value<int?> experience;
  final Value<bool> kappaRequired;
  final Value<String> payload;
  final Value<int> rowid;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.traderId = const Value.absent(),
    this.mapId = const Value.absent(),
    this.minPlayerLevel = const Value.absent(),
    this.experience = const Value.absent(),
    this.kappaRequired = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TasksCompanion.insert({
    required String id,
    required String name,
    this.traderId = const Value.absent(),
    this.mapId = const Value.absent(),
    this.minPlayerLevel = const Value.absent(),
    this.experience = const Value.absent(),
    this.kappaRequired = const Value.absent(),
    required String payload,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       payload = Value(payload);
  static Insertable<Task> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? traderId,
    Expression<String>? mapId,
    Expression<int>? minPlayerLevel,
    Expression<int>? experience,
    Expression<bool>? kappaRequired,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (traderId != null) 'traderId': traderId,
      if (mapId != null) 'mapId': mapId,
      if (minPlayerLevel != null) 'minPlayerLevel': minPlayerLevel,
      if (experience != null) 'experience': experience,
      if (kappaRequired != null) 'kappaRequired': kappaRequired,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TasksCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? traderId,
    Value<String?>? mapId,
    Value<int?>? minPlayerLevel,
    Value<int?>? experience,
    Value<bool>? kappaRequired,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return TasksCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      traderId: traderId ?? this.traderId,
      mapId: mapId ?? this.mapId,
      minPlayerLevel: minPlayerLevel ?? this.minPlayerLevel,
      experience: experience ?? this.experience,
      kappaRequired: kappaRequired ?? this.kappaRequired,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (traderId.present) {
      map['traderId'] = Variable<String>(traderId.value);
    }
    if (mapId.present) {
      map['mapId'] = Variable<String>(mapId.value);
    }
    if (minPlayerLevel.present) {
      map['minPlayerLevel'] = Variable<int>(minPlayerLevel.value);
    }
    if (experience.present) {
      map['experience'] = Variable<int>(experience.value);
    }
    if (kappaRequired.present) {
      map['kappaRequired'] = Variable<bool>(kappaRequired.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('traderId: $traderId, ')
          ..write('mapId: $mapId, ')
          ..write('minPlayerLevel: $minPlayerLevel, ')
          ..write('experience: $experience, ')
          ..write('kappaRequired: $kappaRequired, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskObjectivesTable extends TaskObjectives
    with TableInfo<$TaskObjectivesTable, TaskObjective> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskObjectivesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'taskId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tasks (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _countMeta = const VerificationMeta('count');
  @override
  late final GeneratedColumn<int> count = GeneratedColumn<int>(
    'count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    taskId,
    type,
    description,
    count,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'taskObjectives';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskObjective> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('taskId')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['taskId']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('count')) {
      context.handle(
        _countMeta,
        count.isAcceptableOrUnknown(data['count']!, _countMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskObjective map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskObjective(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}taskId'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      count: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}count'],
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $TaskObjectivesTable createAlias(String alias) {
    return $TaskObjectivesTable(attachedDatabase, alias);
  }
}

class TaskObjective extends DataClass implements Insertable<TaskObjective> {
  /// Upstream objective id.
  final String id;

  /// Owning task; cascades when the task row is replaced.
  final String taskId;

  /// Objective type (`shoot`, `findItem`, `visit`, ...).
  final String type;

  /// Localized objective description.
  final String description;

  /// Required count for countable objectives; `null` for binary ones.
  final int? count;

  /// The complete bundle record as canonical JSON.
  final String payload;
  const TaskObjective({
    required this.id,
    required this.taskId,
    required this.type,
    required this.description,
    this.count,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['taskId'] = Variable<String>(taskId);
    map['type'] = Variable<String>(type);
    map['description'] = Variable<String>(description);
    if (!nullToAbsent || count != null) {
      map['count'] = Variable<int>(count);
    }
    map['payload'] = Variable<String>(payload);
    return map;
  }

  TaskObjectivesCompanion toCompanion(bool nullToAbsent) {
    return TaskObjectivesCompanion(
      id: Value(id),
      taskId: Value(taskId),
      type: Value(type),
      description: Value(description),
      count: count == null && nullToAbsent
          ? const Value.absent()
          : Value(count),
      payload: Value(payload),
    );
  }

  factory TaskObjective.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskObjective(
      id: serializer.fromJson<String>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      type: serializer.fromJson<String>(json['type']),
      description: serializer.fromJson<String>(json['description']),
      count: serializer.fromJson<int?>(json['count']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'taskId': serializer.toJson<String>(taskId),
      'type': serializer.toJson<String>(type),
      'description': serializer.toJson<String>(description),
      'count': serializer.toJson<int?>(count),
      'payload': serializer.toJson<String>(payload),
    };
  }

  TaskObjective copyWith({
    String? id,
    String? taskId,
    String? type,
    String? description,
    Value<int?> count = const Value.absent(),
    String? payload,
  }) => TaskObjective(
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    type: type ?? this.type,
    description: description ?? this.description,
    count: count.present ? count.value : this.count,
    payload: payload ?? this.payload,
  );
  TaskObjective copyWithCompanion(TaskObjectivesCompanion data) {
    return TaskObjective(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      type: data.type.present ? data.type.value : this.type,
      description: data.description.present
          ? data.description.value
          : this.description,
      count: data.count.present ? data.count.value : this.count,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskObjective(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('type: $type, ')
          ..write('description: $description, ')
          ..write('count: $count, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, taskId, type, description, count, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskObjective &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.type == this.type &&
          other.description == this.description &&
          other.count == this.count &&
          other.payload == this.payload);
}

class TaskObjectivesCompanion extends UpdateCompanion<TaskObjective> {
  final Value<String> id;
  final Value<String> taskId;
  final Value<String> type;
  final Value<String> description;
  final Value<int?> count;
  final Value<String> payload;
  final Value<int> rowid;
  const TaskObjectivesCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.type = const Value.absent(),
    this.description = const Value.absent(),
    this.count = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskObjectivesCompanion.insert({
    required String id,
    required String taskId,
    required String type,
    this.description = const Value.absent(),
    this.count = const Value.absent(),
    required String payload,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       taskId = Value(taskId),
       type = Value(type),
       payload = Value(payload);
  static Insertable<TaskObjective> custom({
    Expression<String>? id,
    Expression<String>? taskId,
    Expression<String>? type,
    Expression<String>? description,
    Expression<int>? count,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'taskId': taskId,
      if (type != null) 'type': type,
      if (description != null) 'description': description,
      if (count != null) 'count': count,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskObjectivesCompanion copyWith({
    Value<String>? id,
    Value<String>? taskId,
    Value<String>? type,
    Value<String>? description,
    Value<int?>? count,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return TaskObjectivesCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      type: type ?? this.type,
      description: description ?? this.description,
      count: count ?? this.count,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskId.present) {
      map['taskId'] = Variable<String>(taskId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (count.present) {
      map['count'] = Variable<int>(count.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskObjectivesCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('type: $type, ')
          ..write('description: $description, ')
          ..write('count: $count, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TradersTable extends Traders with TableInfo<$TradersTable, Trader> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TradersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalizedNameMeta = const VerificationMeta(
    'normalizedName',
  );
  @override
  late final GeneratedColumn<String> normalizedName = GeneratedColumn<String>(
    'normalizedName',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, normalizedName, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'traders';
  @override
  VerificationContext validateIntegrity(
    Insertable<Trader> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('normalizedName')) {
      context.handle(
        _normalizedNameMeta,
        normalizedName.isAcceptableOrUnknown(
          data['normalizedName']!,
          _normalizedNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedNameMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Trader map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Trader(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      normalizedName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalizedName'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $TradersTable createAlias(String alias) {
    return $TradersTable(attachedDatabase, alias);
  }
}

class Trader extends DataClass implements Insertable<Trader> {
  final String id;
  final String name;
  final String normalizedName;
  final String payload;
  const Trader({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['normalizedName'] = Variable<String>(normalizedName);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  TradersCompanion toCompanion(bool nullToAbsent) {
    return TradersCompanion(
      id: Value(id),
      name: Value(name),
      normalizedName: Value(normalizedName),
      payload: Value(payload),
    );
  }

  factory Trader.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Trader(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      normalizedName: serializer.fromJson<String>(json['normalizedName']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'normalizedName': serializer.toJson<String>(normalizedName),
      'payload': serializer.toJson<String>(payload),
    };
  }

  Trader copyWith({
    String? id,
    String? name,
    String? normalizedName,
    String? payload,
  }) => Trader(
    id: id ?? this.id,
    name: name ?? this.name,
    normalizedName: normalizedName ?? this.normalizedName,
    payload: payload ?? this.payload,
  );
  Trader copyWithCompanion(TradersCompanion data) {
    return Trader(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      normalizedName: data.normalizedName.present
          ? data.normalizedName.value
          : this.normalizedName,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Trader(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, normalizedName, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Trader &&
          other.id == this.id &&
          other.name == this.name &&
          other.normalizedName == this.normalizedName &&
          other.payload == this.payload);
}

class TradersCompanion extends UpdateCompanion<Trader> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> normalizedName;
  final Value<String> payload;
  final Value<int> rowid;
  const TradersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.normalizedName = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TradersCompanion.insert({
    required String id,
    required String name,
    required String normalizedName,
    required String payload,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       normalizedName = Value(normalizedName),
       payload = Value(payload);
  static Insertable<Trader> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? normalizedName,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (normalizedName != null) 'normalizedName': normalizedName,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TradersCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? normalizedName,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return TradersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (normalizedName.present) {
      map['normalizedName'] = Variable<String>(normalizedName.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TradersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HideoutStationsTable extends HideoutStations
    with TableInfo<$HideoutStationsTable, HideoutStation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HideoutStationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'hideoutStations';
  @override
  VerificationContext validateIntegrity(
    Insertable<HideoutStation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HideoutStation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HideoutStation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $HideoutStationsTable createAlias(String alias) {
    return $HideoutStationsTable(attachedDatabase, alias);
  }
}

class HideoutStation extends DataClass implements Insertable<HideoutStation> {
  final String id;
  final String name;
  final String payload;
  const HideoutStation({
    required this.id,
    required this.name,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  HideoutStationsCompanion toCompanion(bool nullToAbsent) {
    return HideoutStationsCompanion(
      id: Value(id),
      name: Value(name),
      payload: Value(payload),
    );
  }

  factory HideoutStation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HideoutStation(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'payload': serializer.toJson<String>(payload),
    };
  }

  HideoutStation copyWith({String? id, String? name, String? payload}) =>
      HideoutStation(
        id: id ?? this.id,
        name: name ?? this.name,
        payload: payload ?? this.payload,
      );
  HideoutStation copyWithCompanion(HideoutStationsCompanion data) {
    return HideoutStation(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HideoutStation(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HideoutStation &&
          other.id == this.id &&
          other.name == this.name &&
          other.payload == this.payload);
}

class HideoutStationsCompanion extends UpdateCompanion<HideoutStation> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> payload;
  final Value<int> rowid;
  const HideoutStationsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HideoutStationsCompanion.insert({
    required String id,
    required String name,
    required String payload,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       payload = Value(payload);
  static Insertable<HideoutStation> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HideoutStationsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return HideoutStationsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HideoutStationsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CraftsTable extends Crafts with TableInfo<$CraftsTable, Craft> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stationIdMeta = const VerificationMeta(
    'stationId',
  );
  @override
  late final GeneratedColumn<String> stationId = GeneratedColumn<String>(
    'stationId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productItemIdMeta = const VerificationMeta(
    'productItemId',
  );
  @override
  late final GeneratedColumn<String> productItemId = GeneratedColumn<String>(
    'productItemId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, stationId, productItemId, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'crafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Craft> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('stationId')) {
      context.handle(
        _stationIdMeta,
        stationId.isAcceptableOrUnknown(data['stationId']!, _stationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_stationIdMeta);
    }
    if (data.containsKey('productItemId')) {
      context.handle(
        _productItemIdMeta,
        productItemId.isAcceptableOrUnknown(
          data['productItemId']!,
          _productItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_productItemIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Craft map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Craft(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stationId'],
      )!,
      productItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}productItemId'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $CraftsTable createAlias(String alias) {
    return $CraftsTable(attachedDatabase, alias);
  }
}

class Craft extends DataClass implements Insertable<Craft> {
  final String id;
  final String stationId;
  final String productItemId;
  final String payload;
  const Craft({
    required this.id,
    required this.stationId,
    required this.productItemId,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['stationId'] = Variable<String>(stationId);
    map['productItemId'] = Variable<String>(productItemId);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  CraftsCompanion toCompanion(bool nullToAbsent) {
    return CraftsCompanion(
      id: Value(id),
      stationId: Value(stationId),
      productItemId: Value(productItemId),
      payload: Value(payload),
    );
  }

  factory Craft.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Craft(
      id: serializer.fromJson<String>(json['id']),
      stationId: serializer.fromJson<String>(json['stationId']),
      productItemId: serializer.fromJson<String>(json['productItemId']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'stationId': serializer.toJson<String>(stationId),
      'productItemId': serializer.toJson<String>(productItemId),
      'payload': serializer.toJson<String>(payload),
    };
  }

  Craft copyWith({
    String? id,
    String? stationId,
    String? productItemId,
    String? payload,
  }) => Craft(
    id: id ?? this.id,
    stationId: stationId ?? this.stationId,
    productItemId: productItemId ?? this.productItemId,
    payload: payload ?? this.payload,
  );
  Craft copyWithCompanion(CraftsCompanion data) {
    return Craft(
      id: data.id.present ? data.id.value : this.id,
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      productItemId: data.productItemId.present
          ? data.productItemId.value
          : this.productItemId,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Craft(')
          ..write('id: $id, ')
          ..write('stationId: $stationId, ')
          ..write('productItemId: $productItemId, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, stationId, productItemId, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Craft &&
          other.id == this.id &&
          other.stationId == this.stationId &&
          other.productItemId == this.productItemId &&
          other.payload == this.payload);
}

class CraftsCompanion extends UpdateCompanion<Craft> {
  final Value<String> id;
  final Value<String> stationId;
  final Value<String> productItemId;
  final Value<String> payload;
  final Value<int> rowid;
  const CraftsCompanion({
    this.id = const Value.absent(),
    this.stationId = const Value.absent(),
    this.productItemId = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CraftsCompanion.insert({
    required String id,
    required String stationId,
    required String productItemId,
    required String payload,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       stationId = Value(stationId),
       productItemId = Value(productItemId),
       payload = Value(payload);
  static Insertable<Craft> custom({
    Expression<String>? id,
    Expression<String>? stationId,
    Expression<String>? productItemId,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (stationId != null) 'stationId': stationId,
      if (productItemId != null) 'productItemId': productItemId,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CraftsCompanion copyWith({
    Value<String>? id,
    Value<String>? stationId,
    Value<String>? productItemId,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return CraftsCompanion(
      id: id ?? this.id,
      stationId: stationId ?? this.stationId,
      productItemId: productItemId ?? this.productItemId,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (stationId.present) {
      map['stationId'] = Variable<String>(stationId.value);
    }
    if (productItemId.present) {
      map['productItemId'] = Variable<String>(productItemId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CraftsCompanion(')
          ..write('id: $id, ')
          ..write('stationId: $stationId, ')
          ..write('productItemId: $productItemId, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BartersTable extends Barters with TableInfo<$BartersTable, Barter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BartersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'barters';
  @override
  VerificationContext validateIntegrity(
    Insertable<Barter> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Barter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Barter(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $BartersTable createAlias(String alias) {
    return $BartersTable(attachedDatabase, alias);
  }
}

class Barter extends DataClass implements Insertable<Barter> {
  final String id;
  final String payload;
  const Barter({required this.id, required this.payload});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  BartersCompanion toCompanion(bool nullToAbsent) {
    return BartersCompanion(id: Value(id), payload: Value(payload));
  }

  factory Barter.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Barter(
      id: serializer.fromJson<String>(json['id']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'payload': serializer.toJson<String>(payload),
    };
  }

  Barter copyWith({String? id, String? payload}) =>
      Barter(id: id ?? this.id, payload: payload ?? this.payload);
  Barter copyWithCompanion(BartersCompanion data) {
    return Barter(
      id: data.id.present ? data.id.value : this.id,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Barter(')
          ..write('id: $id, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Barter && other.id == this.id && other.payload == this.payload);
}

class BartersCompanion extends UpdateCompanion<Barter> {
  final Value<String> id;
  final Value<String> payload;
  final Value<int> rowid;
  const BartersCompanion({
    this.id = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BartersCompanion.insert({
    required String id,
    required String payload,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       payload = Value(payload);
  static Insertable<Barter> custom({
    Expression<String>? id,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BartersCompanion copyWith({
    Value<String>? id,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return BartersCompanion(
      id: id ?? this.id,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BartersCompanion(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MapsTable extends Maps with TableInfo<$MapsTable, TarkovMap> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MapsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalizedNameMeta = const VerificationMeta(
    'normalizedName',
  );
  @override
  late final GeneratedColumn<String> normalizedName = GeneratedColumn<String>(
    'normalizedName',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, normalizedName, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'maps';
  @override
  VerificationContext validateIntegrity(
    Insertable<TarkovMap> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('normalizedName')) {
      context.handle(
        _normalizedNameMeta,
        normalizedName.isAcceptableOrUnknown(
          data['normalizedName']!,
          _normalizedNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedNameMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TarkovMap map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TarkovMap(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      normalizedName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalizedName'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $MapsTable createAlias(String alias) {
    return $MapsTable(attachedDatabase, alias);
  }
}

class TarkovMap extends DataClass implements Insertable<TarkovMap> {
  final String id;
  final String name;
  final String normalizedName;
  final String payload;
  const TarkovMap({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['normalizedName'] = Variable<String>(normalizedName);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  MapsCompanion toCompanion(bool nullToAbsent) {
    return MapsCompanion(
      id: Value(id),
      name: Value(name),
      normalizedName: Value(normalizedName),
      payload: Value(payload),
    );
  }

  factory TarkovMap.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TarkovMap(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      normalizedName: serializer.fromJson<String>(json['normalizedName']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'normalizedName': serializer.toJson<String>(normalizedName),
      'payload': serializer.toJson<String>(payload),
    };
  }

  TarkovMap copyWith({
    String? id,
    String? name,
    String? normalizedName,
    String? payload,
  }) => TarkovMap(
    id: id ?? this.id,
    name: name ?? this.name,
    normalizedName: normalizedName ?? this.normalizedName,
    payload: payload ?? this.payload,
  );
  TarkovMap copyWithCompanion(MapsCompanion data) {
    return TarkovMap(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      normalizedName: data.normalizedName.present
          ? data.normalizedName.value
          : this.normalizedName,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TarkovMap(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, normalizedName, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TarkovMap &&
          other.id == this.id &&
          other.name == this.name &&
          other.normalizedName == this.normalizedName &&
          other.payload == this.payload);
}

class MapsCompanion extends UpdateCompanion<TarkovMap> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> normalizedName;
  final Value<String> payload;
  final Value<int> rowid;
  const MapsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.normalizedName = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MapsCompanion.insert({
    required String id,
    required String name,
    required String normalizedName,
    required String payload,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       normalizedName = Value(normalizedName),
       payload = Value(payload);
  static Insertable<TarkovMap> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? normalizedName,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (normalizedName != null) 'normalizedName': normalizedName,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MapsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? normalizedName,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return MapsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (normalizedName.present) {
      map['normalizedName'] = Variable<String>(normalizedName.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MapsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GameRecordsTable extends GameRecords
    with TableInfo<$GameRecordsTable, GameRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GameRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [kind, id, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gameRecords';
  @override
  VerificationContext validateIntegrity(
    Insertable<GameRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {kind, id};
  @override
  GameRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GameRecord(
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $GameRecordsTable createAlias(String alias) {
    return $GameRecordsTable(attachedDatabase, alias);
  }
}

class GameRecord extends DataClass implements Insertable<GameRecord> {
  /// Bundle record discriminator (`itemCategory`, `achievement`, ...).
  final String kind;

  /// Upstream identifier of the record.
  final String id;

  /// The complete bundle record as canonical JSON.
  final String payload;
  const GameRecord({
    required this.kind,
    required this.id,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['kind'] = Variable<String>(kind);
    map['id'] = Variable<String>(id);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  GameRecordsCompanion toCompanion(bool nullToAbsent) {
    return GameRecordsCompanion(
      kind: Value(kind),
      id: Value(id),
      payload: Value(payload),
    );
  }

  factory GameRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GameRecord(
      kind: serializer.fromJson<String>(json['kind']),
      id: serializer.fromJson<String>(json['id']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'kind': serializer.toJson<String>(kind),
      'id': serializer.toJson<String>(id),
      'payload': serializer.toJson<String>(payload),
    };
  }

  GameRecord copyWith({String? kind, String? id, String? payload}) =>
      GameRecord(
        kind: kind ?? this.kind,
        id: id ?? this.id,
        payload: payload ?? this.payload,
      );
  GameRecord copyWithCompanion(GameRecordsCompanion data) {
    return GameRecord(
      kind: data.kind.present ? data.kind.value : this.kind,
      id: data.id.present ? data.id.value : this.id,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GameRecord(')
          ..write('kind: $kind, ')
          ..write('id: $id, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(kind, id, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GameRecord &&
          other.kind == this.kind &&
          other.id == this.id &&
          other.payload == this.payload);
}

class GameRecordsCompanion extends UpdateCompanion<GameRecord> {
  final Value<String> kind;
  final Value<String> id;
  final Value<String> payload;
  final Value<int> rowid;
  const GameRecordsCompanion({
    this.kind = const Value.absent(),
    this.id = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GameRecordsCompanion.insert({
    required String kind,
    required String id,
    required String payload,
    this.rowid = const Value.absent(),
  }) : kind = Value(kind),
       id = Value(id),
       payload = Value(payload);
  static Insertable<GameRecord> custom({
    Expression<String>? kind,
    Expression<String>? id,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (kind != null) 'kind': kind,
      if (id != null) 'id': id,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GameRecordsCompanion copyWith({
    Value<String>? kind,
    Value<String>? id,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return GameRecordsCompanion(
      kind: kind ?? this.kind,
      id: id ?? this.id,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GameRecordsCompanion(')
          ..write('kind: $kind, ')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PriceHistoryTable extends PriceHistory
    with TableInfo<$PriceHistoryTable, PriceHistoryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PriceHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'itemId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _observedAtMeta = const VerificationMeta(
    'observedAt',
  );
  @override
  late final GeneratedColumn<DateTime> observedAt = GeneratedColumn<DateTime>(
    'observedAt',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<int> price = GeneratedColumn<int>(
    'price',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceMinMeta = const VerificationMeta(
    'priceMin',
  );
  @override
  late final GeneratedColumn<int> priceMin = GeneratedColumn<int>(
    'priceMin',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [itemId, observedAt, price, priceMin];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'priceHistory';
  @override
  VerificationContext validateIntegrity(
    Insertable<PriceHistoryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('itemId')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['itemId']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('observedAt')) {
      context.handle(
        _observedAtMeta,
        observedAt.isAcceptableOrUnknown(data['observedAt']!, _observedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_observedAtMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
        _priceMeta,
        price.isAcceptableOrUnknown(data['price']!, _priceMeta),
      );
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('priceMin')) {
      context.handle(
        _priceMinMeta,
        priceMin.isAcceptableOrUnknown(data['priceMin']!, _priceMinMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {itemId, observedAt};
  @override
  PriceHistoryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PriceHistoryEntry(
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}itemId'],
      )!,
      observedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}observedAt'],
      )!,
      price: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price'],
      )!,
      priceMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priceMin'],
      ),
    );
  }

  @override
  $PriceHistoryTable createAlias(String alias) {
    return $PriceHistoryTable(attachedDatabase, alias);
  }
}

class PriceHistoryEntry extends DataClass
    implements Insertable<PriceHistoryEntry> {
  final String itemId;
  final DateTime observedAt;
  final int price;
  final int? priceMin;
  const PriceHistoryEntry({
    required this.itemId,
    required this.observedAt,
    required this.price,
    this.priceMin,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['itemId'] = Variable<String>(itemId);
    map['observedAt'] = Variable<DateTime>(observedAt);
    map['price'] = Variable<int>(price);
    if (!nullToAbsent || priceMin != null) {
      map['priceMin'] = Variable<int>(priceMin);
    }
    return map;
  }

  PriceHistoryCompanion toCompanion(bool nullToAbsent) {
    return PriceHistoryCompanion(
      itemId: Value(itemId),
      observedAt: Value(observedAt),
      price: Value(price),
      priceMin: priceMin == null && nullToAbsent
          ? const Value.absent()
          : Value(priceMin),
    );
  }

  factory PriceHistoryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PriceHistoryEntry(
      itemId: serializer.fromJson<String>(json['itemId']),
      observedAt: serializer.fromJson<DateTime>(json['observedAt']),
      price: serializer.fromJson<int>(json['price']),
      priceMin: serializer.fromJson<int?>(json['priceMin']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'itemId': serializer.toJson<String>(itemId),
      'observedAt': serializer.toJson<DateTime>(observedAt),
      'price': serializer.toJson<int>(price),
      'priceMin': serializer.toJson<int?>(priceMin),
    };
  }

  PriceHistoryEntry copyWith({
    String? itemId,
    DateTime? observedAt,
    int? price,
    Value<int?> priceMin = const Value.absent(),
  }) => PriceHistoryEntry(
    itemId: itemId ?? this.itemId,
    observedAt: observedAt ?? this.observedAt,
    price: price ?? this.price,
    priceMin: priceMin.present ? priceMin.value : this.priceMin,
  );
  PriceHistoryEntry copyWithCompanion(PriceHistoryCompanion data) {
    return PriceHistoryEntry(
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      observedAt: data.observedAt.present
          ? data.observedAt.value
          : this.observedAt,
      price: data.price.present ? data.price.value : this.price,
      priceMin: data.priceMin.present ? data.priceMin.value : this.priceMin,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PriceHistoryEntry(')
          ..write('itemId: $itemId, ')
          ..write('observedAt: $observedAt, ')
          ..write('price: $price, ')
          ..write('priceMin: $priceMin')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(itemId, observedAt, price, priceMin);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PriceHistoryEntry &&
          other.itemId == this.itemId &&
          other.observedAt == this.observedAt &&
          other.price == this.price &&
          other.priceMin == this.priceMin);
}

class PriceHistoryCompanion extends UpdateCompanion<PriceHistoryEntry> {
  final Value<String> itemId;
  final Value<DateTime> observedAt;
  final Value<int> price;
  final Value<int?> priceMin;
  final Value<int> rowid;
  const PriceHistoryCompanion({
    this.itemId = const Value.absent(),
    this.observedAt = const Value.absent(),
    this.price = const Value.absent(),
    this.priceMin = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PriceHistoryCompanion.insert({
    required String itemId,
    required DateTime observedAt,
    required int price,
    this.priceMin = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : itemId = Value(itemId),
       observedAt = Value(observedAt),
       price = Value(price);
  static Insertable<PriceHistoryEntry> custom({
    Expression<String>? itemId,
    Expression<DateTime>? observedAt,
    Expression<int>? price,
    Expression<int>? priceMin,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (itemId != null) 'itemId': itemId,
      if (observedAt != null) 'observedAt': observedAt,
      if (price != null) 'price': price,
      if (priceMin != null) 'priceMin': priceMin,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PriceHistoryCompanion copyWith({
    Value<String>? itemId,
    Value<DateTime>? observedAt,
    Value<int>? price,
    Value<int?>? priceMin,
    Value<int>? rowid,
  }) {
    return PriceHistoryCompanion(
      itemId: itemId ?? this.itemId,
      observedAt: observedAt ?? this.observedAt,
      price: price ?? this.price,
      priceMin: priceMin ?? this.priceMin,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (itemId.present) {
      map['itemId'] = Variable<String>(itemId.value);
    }
    if (observedAt.present) {
      map['observedAt'] = Variable<DateTime>(observedAt.value);
    }
    if (price.present) {
      map['price'] = Variable<int>(price.value);
    }
    if (priceMin.present) {
      map['priceMin'] = Variable<int>(priceMin.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PriceHistoryCompanion(')
          ..write('itemId: $itemId, ')
          ..write('observedAt: $observedAt, ')
          ..write('price: $price, ')
          ..write('priceMin: $priceMin, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProfilesTable extends Profiles with TableInfo<$ProfilesTable, Profile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gameModeMeta = const VerificationMeta(
    'gameMode',
  );
  @override
  late final GeneratedColumn<String> gameMode = GeneratedColumn<String>(
    'gameMode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _playerLevelMeta = const VerificationMeta(
    'playerLevel',
  );
  @override
  late final GeneratedColumn<int> playerLevel = GeneratedColumn<int>(
    'playerLevel',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'createdAt',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updatedAt',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    gameMode,
    playerLevel,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<Profile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('gameMode')) {
      context.handle(
        _gameModeMeta,
        gameMode.isAcceptableOrUnknown(data['gameMode']!, _gameModeMeta),
      );
    } else if (isInserting) {
      context.missing(_gameModeMeta);
    }
    if (data.containsKey('playerLevel')) {
      context.handle(
        _playerLevelMeta,
        playerLevel.isAcceptableOrUnknown(
          data['playerLevel']!,
          _playerLevelMeta,
        ),
      );
    }
    if (data.containsKey('createdAt')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['createdAt']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updatedAt')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updatedAt']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Profile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Profile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      gameMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gameMode'],
      )!,
      playerLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}playerLevel'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}createdAt'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updatedAt'],
      )!,
    );
  }

  @override
  $ProfilesTable createAlias(String alias) {
    return $ProfilesTable(attachedDatabase, alias);
  }
}

class Profile extends DataClass implements Insertable<Profile> {
  /// Profile id. Stable for the lifetime of the profile.
  final String id;

  /// `regular`, `pve` or `pvp-season`; at most one profile per mode.
  final String gameMode;

  /// Player level recorded by the user.
  final int playerLevel;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Profile({
    required this.id,
    required this.gameMode,
    required this.playerLevel,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['gameMode'] = Variable<String>(gameMode);
    map['playerLevel'] = Variable<int>(playerLevel);
    map['createdAt'] = Variable<DateTime>(createdAt);
    map['updatedAt'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProfilesCompanion toCompanion(bool nullToAbsent) {
    return ProfilesCompanion(
      id: Value(id),
      gameMode: Value(gameMode),
      playerLevel: Value(playerLevel),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Profile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Profile(
      id: serializer.fromJson<String>(json['id']),
      gameMode: serializer.fromJson<String>(json['gameMode']),
      playerLevel: serializer.fromJson<int>(json['playerLevel']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'gameMode': serializer.toJson<String>(gameMode),
      'playerLevel': serializer.toJson<int>(playerLevel),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Profile copyWith({
    String? id,
    String? gameMode,
    int? playerLevel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Profile(
    id: id ?? this.id,
    gameMode: gameMode ?? this.gameMode,
    playerLevel: playerLevel ?? this.playerLevel,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Profile copyWithCompanion(ProfilesCompanion data) {
    return Profile(
      id: data.id.present ? data.id.value : this.id,
      gameMode: data.gameMode.present ? data.gameMode.value : this.gameMode,
      playerLevel: data.playerLevel.present
          ? data.playerLevel.value
          : this.playerLevel,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Profile(')
          ..write('id: $id, ')
          ..write('gameMode: $gameMode, ')
          ..write('playerLevel: $playerLevel, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, gameMode, playerLevel, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Profile &&
          other.id == this.id &&
          other.gameMode == this.gameMode &&
          other.playerLevel == this.playerLevel &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProfilesCompanion extends UpdateCompanion<Profile> {
  final Value<String> id;
  final Value<String> gameMode;
  final Value<int> playerLevel;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ProfilesCompanion({
    this.id = const Value.absent(),
    this.gameMode = const Value.absent(),
    this.playerLevel = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfilesCompanion.insert({
    required String id,
    required String gameMode,
    this.playerLevel = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       gameMode = Value(gameMode),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Profile> custom({
    Expression<String>? id,
    Expression<String>? gameMode,
    Expression<int>? playerLevel,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (gameMode != null) 'gameMode': gameMode,
      if (playerLevel != null) 'playerLevel': playerLevel,
      if (createdAt != null) 'createdAt': createdAt,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfilesCompanion copyWith({
    Value<String>? id,
    Value<String>? gameMode,
    Value<int>? playerLevel,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ProfilesCompanion(
      id: id ?? this.id,
      gameMode: gameMode ?? this.gameMode,
      playerLevel: playerLevel ?? this.playerLevel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (gameMode.present) {
      map['gameMode'] = Variable<String>(gameMode.value);
    }
    if (playerLevel.present) {
      map['playerLevel'] = Variable<int>(playerLevel.value);
    }
    if (createdAt.present) {
      map['createdAt'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updatedAt'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfilesCompanion(')
          ..write('id: $id, ')
          ..write('gameMode: $gameMode, ')
          ..write('playerLevel: $playerLevel, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QuestProgressTable extends QuestProgress
    with TableInfo<$QuestProgressTable, QuestProgressEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QuestProgressTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profileId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES profiles (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _questIdMeta = const VerificationMeta(
    'questId',
  );
  @override
  late final GeneratedColumn<String> questId = GeneratedColumn<String>(
    'questId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updatedAt',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [profileId, questId, state, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'questProgress';
  @override
  VerificationContext validateIntegrity(
    Insertable<QuestProgressEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('profileId')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profileId']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('questId')) {
      context.handle(
        _questIdMeta,
        questId.isAcceptableOrUnknown(data['questId']!, _questIdMeta),
      );
    } else if (isInserting) {
      context.missing(_questIdMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('updatedAt')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updatedAt']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {profileId, questId};
  @override
  QuestProgressEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QuestProgressEntry(
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profileId'],
      )!,
      questId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}questId'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updatedAt'],
      )!,
    );
  }

  @override
  $QuestProgressTable createAlias(String alias) {
    return $QuestProgressTable(attachedDatabase, alias);
  }
}

class QuestProgressEntry extends DataClass
    implements Insertable<QuestProgressEntry> {
  final String profileId;

  /// Upstream quest id; may reference a quest absent from the current dataset.
  final String questId;

  /// `in-progress`, `completed` or `failed`. Availability (locked/available) is
  /// derived and never stored.
  final String state;
  final DateTime updatedAt;
  const QuestProgressEntry({
    required this.profileId,
    required this.questId,
    required this.state,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['profileId'] = Variable<String>(profileId);
    map['questId'] = Variable<String>(questId);
    map['state'] = Variable<String>(state);
    map['updatedAt'] = Variable<DateTime>(updatedAt);
    return map;
  }

  QuestProgressCompanion toCompanion(bool nullToAbsent) {
    return QuestProgressCompanion(
      profileId: Value(profileId),
      questId: Value(questId),
      state: Value(state),
      updatedAt: Value(updatedAt),
    );
  }

  factory QuestProgressEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QuestProgressEntry(
      profileId: serializer.fromJson<String>(json['profileId']),
      questId: serializer.fromJson<String>(json['questId']),
      state: serializer.fromJson<String>(json['state']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'profileId': serializer.toJson<String>(profileId),
      'questId': serializer.toJson<String>(questId),
      'state': serializer.toJson<String>(state),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  QuestProgressEntry copyWith({
    String? profileId,
    String? questId,
    String? state,
    DateTime? updatedAt,
  }) => QuestProgressEntry(
    profileId: profileId ?? this.profileId,
    questId: questId ?? this.questId,
    state: state ?? this.state,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  QuestProgressEntry copyWithCompanion(QuestProgressCompanion data) {
    return QuestProgressEntry(
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      questId: data.questId.present ? data.questId.value : this.questId,
      state: data.state.present ? data.state.value : this.state,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QuestProgressEntry(')
          ..write('profileId: $profileId, ')
          ..write('questId: $questId, ')
          ..write('state: $state, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(profileId, questId, state, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QuestProgressEntry &&
          other.profileId == this.profileId &&
          other.questId == this.questId &&
          other.state == this.state &&
          other.updatedAt == this.updatedAt);
}

class QuestProgressCompanion extends UpdateCompanion<QuestProgressEntry> {
  final Value<String> profileId;
  final Value<String> questId;
  final Value<String> state;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const QuestProgressCompanion({
    this.profileId = const Value.absent(),
    this.questId = const Value.absent(),
    this.state = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  QuestProgressCompanion.insert({
    required String profileId,
    required String questId,
    required String state,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : profileId = Value(profileId),
       questId = Value(questId),
       state = Value(state),
       updatedAt = Value(updatedAt);
  static Insertable<QuestProgressEntry> custom({
    Expression<String>? profileId,
    Expression<String>? questId,
    Expression<String>? state,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (profileId != null) 'profileId': profileId,
      if (questId != null) 'questId': questId,
      if (state != null) 'state': state,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  QuestProgressCompanion copyWith({
    Value<String>? profileId,
    Value<String>? questId,
    Value<String>? state,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return QuestProgressCompanion(
      profileId: profileId ?? this.profileId,
      questId: questId ?? this.questId,
      state: state ?? this.state,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (profileId.present) {
      map['profileId'] = Variable<String>(profileId.value);
    }
    if (questId.present) {
      map['questId'] = Variable<String>(questId.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (updatedAt.present) {
      map['updatedAt'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QuestProgressCompanion(')
          ..write('profileId: $profileId, ')
          ..write('questId: $questId, ')
          ..write('state: $state, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ObjectiveProgressTable extends ObjectiveProgress
    with TableInfo<$ObjectiveProgressTable, ObjectiveProgressEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ObjectiveProgressTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profileId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES profiles (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _questIdMeta = const VerificationMeta(
    'questId',
  );
  @override
  late final GeneratedColumn<String> questId = GeneratedColumn<String>(
    'questId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _objectiveIdMeta = const VerificationMeta(
    'objectiveId',
  );
  @override
  late final GeneratedColumn<String> objectiveId = GeneratedColumn<String>(
    'objectiveId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countMeta = const VerificationMeta('count');
  @override
  late final GeneratedColumn<int> count = GeneratedColumn<int>(
    'count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updatedAt',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    profileId,
    questId,
    objectiveId,
    count,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'objectiveProgress';
  @override
  VerificationContext validateIntegrity(
    Insertable<ObjectiveProgressEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('profileId')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profileId']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('questId')) {
      context.handle(
        _questIdMeta,
        questId.isAcceptableOrUnknown(data['questId']!, _questIdMeta),
      );
    } else if (isInserting) {
      context.missing(_questIdMeta);
    }
    if (data.containsKey('objectiveId')) {
      context.handle(
        _objectiveIdMeta,
        objectiveId.isAcceptableOrUnknown(
          data['objectiveId']!,
          _objectiveIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_objectiveIdMeta);
    }
    if (data.containsKey('count')) {
      context.handle(
        _countMeta,
        count.isAcceptableOrUnknown(data['count']!, _countMeta),
      );
    }
    if (data.containsKey('updatedAt')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updatedAt']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {profileId, questId, objectiveId};
  @override
  ObjectiveProgressEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ObjectiveProgressEntry(
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profileId'],
      )!,
      questId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}questId'],
      )!,
      objectiveId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}objectiveId'],
      )!,
      count: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}count'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updatedAt'],
      )!,
    );
  }

  @override
  $ObjectiveProgressTable createAlias(String alias) {
    return $ObjectiveProgressTable(attachedDatabase, alias);
  }
}

class ObjectiveProgressEntry extends DataClass
    implements Insertable<ObjectiveProgressEntry> {
  final String profileId;
  final String questId;
  final String objectiveId;

  /// Recorded count, clamped to the objective's required count by the tracker.
  final int count;
  final DateTime updatedAt;
  const ObjectiveProgressEntry({
    required this.profileId,
    required this.questId,
    required this.objectiveId,
    required this.count,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['profileId'] = Variable<String>(profileId);
    map['questId'] = Variable<String>(questId);
    map['objectiveId'] = Variable<String>(objectiveId);
    map['count'] = Variable<int>(count);
    map['updatedAt'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ObjectiveProgressCompanion toCompanion(bool nullToAbsent) {
    return ObjectiveProgressCompanion(
      profileId: Value(profileId),
      questId: Value(questId),
      objectiveId: Value(objectiveId),
      count: Value(count),
      updatedAt: Value(updatedAt),
    );
  }

  factory ObjectiveProgressEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ObjectiveProgressEntry(
      profileId: serializer.fromJson<String>(json['profileId']),
      questId: serializer.fromJson<String>(json['questId']),
      objectiveId: serializer.fromJson<String>(json['objectiveId']),
      count: serializer.fromJson<int>(json['count']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'profileId': serializer.toJson<String>(profileId),
      'questId': serializer.toJson<String>(questId),
      'objectiveId': serializer.toJson<String>(objectiveId),
      'count': serializer.toJson<int>(count),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ObjectiveProgressEntry copyWith({
    String? profileId,
    String? questId,
    String? objectiveId,
    int? count,
    DateTime? updatedAt,
  }) => ObjectiveProgressEntry(
    profileId: profileId ?? this.profileId,
    questId: questId ?? this.questId,
    objectiveId: objectiveId ?? this.objectiveId,
    count: count ?? this.count,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ObjectiveProgressEntry copyWithCompanion(ObjectiveProgressCompanion data) {
    return ObjectiveProgressEntry(
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      questId: data.questId.present ? data.questId.value : this.questId,
      objectiveId: data.objectiveId.present
          ? data.objectiveId.value
          : this.objectiveId,
      count: data.count.present ? data.count.value : this.count,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ObjectiveProgressEntry(')
          ..write('profileId: $profileId, ')
          ..write('questId: $questId, ')
          ..write('objectiveId: $objectiveId, ')
          ..write('count: $count, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(profileId, questId, objectiveId, count, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ObjectiveProgressEntry &&
          other.profileId == this.profileId &&
          other.questId == this.questId &&
          other.objectiveId == this.objectiveId &&
          other.count == this.count &&
          other.updatedAt == this.updatedAt);
}

class ObjectiveProgressCompanion
    extends UpdateCompanion<ObjectiveProgressEntry> {
  final Value<String> profileId;
  final Value<String> questId;
  final Value<String> objectiveId;
  final Value<int> count;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ObjectiveProgressCompanion({
    this.profileId = const Value.absent(),
    this.questId = const Value.absent(),
    this.objectiveId = const Value.absent(),
    this.count = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ObjectiveProgressCompanion.insert({
    required String profileId,
    required String questId,
    required String objectiveId,
    this.count = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : profileId = Value(profileId),
       questId = Value(questId),
       objectiveId = Value(objectiveId),
       updatedAt = Value(updatedAt);
  static Insertable<ObjectiveProgressEntry> custom({
    Expression<String>? profileId,
    Expression<String>? questId,
    Expression<String>? objectiveId,
    Expression<int>? count,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (profileId != null) 'profileId': profileId,
      if (questId != null) 'questId': questId,
      if (objectiveId != null) 'objectiveId': objectiveId,
      if (count != null) 'count': count,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ObjectiveProgressCompanion copyWith({
    Value<String>? profileId,
    Value<String>? questId,
    Value<String>? objectiveId,
    Value<int>? count,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ObjectiveProgressCompanion(
      profileId: profileId ?? this.profileId,
      questId: questId ?? this.questId,
      objectiveId: objectiveId ?? this.objectiveId,
      count: count ?? this.count,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (profileId.present) {
      map['profileId'] = Variable<String>(profileId.value);
    }
    if (questId.present) {
      map['questId'] = Variable<String>(questId.value);
    }
    if (objectiveId.present) {
      map['objectiveId'] = Variable<String>(objectiveId.value);
    }
    if (count.present) {
      map['count'] = Variable<int>(count.value);
    }
    if (updatedAt.present) {
      map['updatedAt'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ObjectiveProgressCompanion(')
          ..write('profileId: $profileId, ')
          ..write('questId: $questId, ')
          ..write('objectiveId: $objectiveId, ')
          ..write('count: $count, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'appSettings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSetting copyWith({String? key, String? value}) =>
      AppSetting(key: key ?? this.key, value: value ?? this.value);
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $DatasetStatesTable datasetStates = $DatasetStatesTable(this);
  late final $RemoteManifestsTable remoteManifests = $RemoteManifestsTable(
    this,
  );
  late final $ItemsTable items = $ItemsTable(this);
  late final $ItemTypesTable itemTypes = $ItemTypesTable(this);
  late final $ItemCategoriesTable itemCategories = $ItemCategoriesTable(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $TaskObjectivesTable taskObjectives = $TaskObjectivesTable(this);
  late final $TradersTable traders = $TradersTable(this);
  late final $HideoutStationsTable hideoutStations = $HideoutStationsTable(
    this,
  );
  late final $CraftsTable crafts = $CraftsTable(this);
  late final $BartersTable barters = $BartersTable(this);
  late final $MapsTable maps = $MapsTable(this);
  late final $GameRecordsTable gameRecords = $GameRecordsTable(this);
  late final $PriceHistoryTable priceHistory = $PriceHistoryTable(this);
  late final $ProfilesTable profiles = $ProfilesTable(this);
  late final $QuestProgressTable questProgress = $QuestProgressTable(this);
  late final $ObjectiveProgressTable objectiveProgress =
      $ObjectiveProgressTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final Index itemsNormalizedName = Index(
    'itemsNormalizedName',
    'CREATE INDEX itemsNormalizedName ON items (normalizedName)',
  );
  late final Index itemsLastLowPrice = Index(
    'itemsLastLowPrice',
    'CREATE INDEX itemsLastLowPrice ON items (lastLowPrice)',
  );
  late final Index itemsAvg24hPrice = Index(
    'itemsAvg24hPrice',
    'CREATE INDEX itemsAvg24hPrice ON items (avg24hPrice)',
  );
  late final Index itemTypesType = Index(
    'itemTypesType',
    'CREATE INDEX itemTypesType ON itemTypes (type)',
  );
  late final Index itemCategoriesCategory = Index(
    'itemCategoriesCategory',
    'CREATE INDEX itemCategoriesCategory ON itemCategories (categoryKind, categoryId)',
  );
  late final Index tasksTraderId = Index(
    'tasksTraderId',
    'CREATE INDEX tasksTraderId ON tasks (traderId)',
  );
  late final Index tasksMapId = Index(
    'tasksMapId',
    'CREATE INDEX tasksMapId ON tasks (mapId)',
  );
  late final Index tasksMinPlayerLevel = Index(
    'tasksMinPlayerLevel',
    'CREATE INDEX tasksMinPlayerLevel ON tasks (minPlayerLevel)',
  );
  late final Index taskObjectivesTaskId = Index(
    'taskObjectivesTaskId',
    'CREATE INDEX taskObjectivesTaskId ON taskObjectives (taskId)',
  );
  late final Index tradersNormalizedName = Index(
    'tradersNormalizedName',
    'CREATE INDEX tradersNormalizedName ON traders (normalizedName)',
  );
  late final Index craftsStationId = Index(
    'craftsStationId',
    'CREATE INDEX craftsStationId ON crafts (stationId)',
  );
  late final Index craftsProductItemId = Index(
    'craftsProductItemId',
    'CREATE INDEX craftsProductItemId ON crafts (productItemId)',
  );
  late final Index mapsNormalizedName = Index(
    'mapsNormalizedName',
    'CREATE INDEX mapsNormalizedName ON maps (normalizedName)',
  );
  late final Index gameRecordsKind = Index(
    'gameRecordsKind',
    'CREATE INDEX gameRecordsKind ON gameRecords (kind)',
  );
  late final Index priceHistoryItemId = Index(
    'priceHistoryItemId',
    'CREATE INDEX priceHistoryItemId ON priceHistory (itemId)',
  );
  late final Index questProgressQuestId = Index(
    'questProgressQuestId',
    'CREATE INDEX questProgressQuestId ON questProgress (questId)',
  );
  late final Index objectiveProgressQuestId = Index(
    'objectiveProgressQuestId',
    'CREATE INDEX objectiveProgressQuestId ON objectiveProgress (questId)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    datasetStates,
    remoteManifests,
    items,
    itemTypes,
    itemCategories,
    tasks,
    taskObjectives,
    traders,
    hideoutStations,
    crafts,
    barters,
    maps,
    gameRecords,
    priceHistory,
    profiles,
    questProgress,
    objectiveProgress,
    appSettings,
    itemsNormalizedName,
    itemsLastLowPrice,
    itemsAvg24hPrice,
    itemTypesType,
    itemCategoriesCategory,
    tasksTraderId,
    tasksMapId,
    tasksMinPlayerLevel,
    taskObjectivesTaskId,
    tradersNormalizedName,
    craftsStationId,
    craftsProductItemId,
    mapsNormalizedName,
    gameRecordsKind,
    priceHistoryItemId,
    questProgressQuestId,
    objectiveProgressQuestId,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'items',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('itemTypes', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'items',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('itemCategories', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('taskObjectives', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'profiles',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('questProgress', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'profiles',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('objectiveProgress', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$DatasetStatesTableCreateCompanionBuilder =
    DatasetStatesCompanion Function({
      required String mode,
      required String dataset,
      required String checksum,
      required int schemaVersion,
      required int records,
      Value<DateTime?> sourceUpdatedAt,
      required DateTime appliedAt,
      Value<int> rowid,
    });
typedef $$DatasetStatesTableUpdateCompanionBuilder =
    DatasetStatesCompanion Function({
      Value<String> mode,
      Value<String> dataset,
      Value<String> checksum,
      Value<int> schemaVersion,
      Value<int> records,
      Value<DateTime?> sourceUpdatedAt,
      Value<DateTime> appliedAt,
      Value<int> rowid,
    });

class $$DatasetStatesTableFilterComposer
    extends Composer<_$AppDatabase, $DatasetStatesTable> {
  $$DatasetStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataset => $composableBuilder(
    column: $table.dataset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get records => $composableBuilder(
    column: $table.records,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sourceUpdatedAt => $composableBuilder(
    column: $table.sourceUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get appliedAt => $composableBuilder(
    column: $table.appliedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DatasetStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $DatasetStatesTable> {
  $$DatasetStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataset => $composableBuilder(
    column: $table.dataset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get records => $composableBuilder(
    column: $table.records,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sourceUpdatedAt => $composableBuilder(
    column: $table.sourceUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get appliedAt => $composableBuilder(
    column: $table.appliedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DatasetStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DatasetStatesTable> {
  $$DatasetStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get dataset =>
      $composableBuilder(column: $table.dataset, builder: (column) => column);

  GeneratedColumn<String> get checksum =>
      $composableBuilder(column: $table.checksum, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get records =>
      $composableBuilder(column: $table.records, builder: (column) => column);

  GeneratedColumn<DateTime> get sourceUpdatedAt => $composableBuilder(
    column: $table.sourceUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get appliedAt =>
      $composableBuilder(column: $table.appliedAt, builder: (column) => column);
}

class $$DatasetStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DatasetStatesTable,
          DatasetState,
          $$DatasetStatesTableFilterComposer,
          $$DatasetStatesTableOrderingComposer,
          $$DatasetStatesTableAnnotationComposer,
          $$DatasetStatesTableCreateCompanionBuilder,
          $$DatasetStatesTableUpdateCompanionBuilder,
          (
            DatasetState,
            BaseReferences<_$AppDatabase, $DatasetStatesTable, DatasetState>,
          ),
          DatasetState,
          PrefetchHooks Function()
        > {
  $$DatasetStatesTableTableManager(_$AppDatabase db, $DatasetStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DatasetStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DatasetStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DatasetStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> mode = const Value.absent(),
                Value<String> dataset = const Value.absent(),
                Value<String> checksum = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<int> records = const Value.absent(),
                Value<DateTime?> sourceUpdatedAt = const Value.absent(),
                Value<DateTime> appliedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DatasetStatesCompanion(
                mode: mode,
                dataset: dataset,
                checksum: checksum,
                schemaVersion: schemaVersion,
                records: records,
                sourceUpdatedAt: sourceUpdatedAt,
                appliedAt: appliedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mode,
                required String dataset,
                required String checksum,
                required int schemaVersion,
                required int records,
                Value<DateTime?> sourceUpdatedAt = const Value.absent(),
                required DateTime appliedAt,
                Value<int> rowid = const Value.absent(),
              }) => DatasetStatesCompanion.insert(
                mode: mode,
                dataset: dataset,
                checksum: checksum,
                schemaVersion: schemaVersion,
                records: records,
                sourceUpdatedAt: sourceUpdatedAt,
                appliedAt: appliedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DatasetStatesTable, DatasetState>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $DatasetStatesTable,
                    DatasetState
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DatasetStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DatasetStatesTable,
      DatasetState,
      $$DatasetStatesTableFilterComposer,
      $$DatasetStatesTableOrderingComposer,
      $$DatasetStatesTableAnnotationComposer,
      $$DatasetStatesTableCreateCompanionBuilder,
      $$DatasetStatesTableUpdateCompanionBuilder,
      (
        DatasetState,
        BaseReferences<_$AppDatabase, $DatasetStatesTable, DatasetState>,
      ),
      DatasetState,
      PrefetchHooks Function()
    >;
typedef $$RemoteManifestsTableCreateCompanionBuilder =
    RemoteManifestsCompanion Function({
      required String mode,
      Value<String?> etag,
      Value<String?> lastModified,
      required String manifestJson,
      Value<String?> manifestGeneratedAt,
      required DateTime lastCheckedAt,
      Value<DateTime?> lastChangedAt,
      required String contentHash,
      Value<int> rowid,
    });
typedef $$RemoteManifestsTableUpdateCompanionBuilder =
    RemoteManifestsCompanion Function({
      Value<String> mode,
      Value<String?> etag,
      Value<String?> lastModified,
      Value<String> manifestJson,
      Value<String?> manifestGeneratedAt,
      Value<DateTime> lastCheckedAt,
      Value<DateTime?> lastChangedAt,
      Value<String> contentHash,
      Value<int> rowid,
    });

class $$RemoteManifestsTableFilterComposer
    extends Composer<_$AppDatabase, $RemoteManifestsTable> {
  $$RemoteManifestsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manifestGeneratedAt => $composableBuilder(
    column: $table.manifestGeneratedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastCheckedAt => $composableBuilder(
    column: $table.lastCheckedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastChangedAt => $composableBuilder(
    column: $table.lastChangedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RemoteManifestsTableOrderingComposer
    extends Composer<_$AppDatabase, $RemoteManifestsTable> {
  $$RemoteManifestsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manifestGeneratedAt => $composableBuilder(
    column: $table.manifestGeneratedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastCheckedAt => $composableBuilder(
    column: $table.lastCheckedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastChangedAt => $composableBuilder(
    column: $table.lastChangedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RemoteManifestsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RemoteManifestsTable> {
  $$RemoteManifestsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => column,
  );

  GeneratedColumn<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get manifestGeneratedAt => $composableBuilder(
    column: $table.manifestGeneratedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastCheckedAt => $composableBuilder(
    column: $table.lastCheckedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastChangedAt => $composableBuilder(
    column: $table.lastChangedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );
}

class $$RemoteManifestsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RemoteManifestsTable,
          RemoteManifestRecord,
          $$RemoteManifestsTableFilterComposer,
          $$RemoteManifestsTableOrderingComposer,
          $$RemoteManifestsTableAnnotationComposer,
          $$RemoteManifestsTableCreateCompanionBuilder,
          $$RemoteManifestsTableUpdateCompanionBuilder,
          (
            RemoteManifestRecord,
            BaseReferences<
              _$AppDatabase,
              $RemoteManifestsTable,
              RemoteManifestRecord
            >,
          ),
          RemoteManifestRecord,
          PrefetchHooks Function()
        > {
  $$RemoteManifestsTableTableManager(
    _$AppDatabase db,
    $RemoteManifestsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RemoteManifestsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RemoteManifestsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RemoteManifestsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> mode = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<String?> lastModified = const Value.absent(),
                Value<String> manifestJson = const Value.absent(),
                Value<String?> manifestGeneratedAt = const Value.absent(),
                Value<DateTime> lastCheckedAt = const Value.absent(),
                Value<DateTime?> lastChangedAt = const Value.absent(),
                Value<String> contentHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RemoteManifestsCompanion(
                mode: mode,
                etag: etag,
                lastModified: lastModified,
                manifestJson: manifestJson,
                manifestGeneratedAt: manifestGeneratedAt,
                lastCheckedAt: lastCheckedAt,
                lastChangedAt: lastChangedAt,
                contentHash: contentHash,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mode,
                Value<String?> etag = const Value.absent(),
                Value<String?> lastModified = const Value.absent(),
                required String manifestJson,
                Value<String?> manifestGeneratedAt = const Value.absent(),
                required DateTime lastCheckedAt,
                Value<DateTime?> lastChangedAt = const Value.absent(),
                required String contentHash,
                Value<int> rowid = const Value.absent(),
              }) => RemoteManifestsCompanion.insert(
                mode: mode,
                etag: etag,
                lastModified: lastModified,
                manifestJson: manifestJson,
                manifestGeneratedAt: manifestGeneratedAt,
                lastCheckedAt: lastCheckedAt,
                lastChangedAt: lastChangedAt,
                contentHash: contentHash,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RemoteManifestsTable, RemoteManifestRecord>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $RemoteManifestsTable,
                    RemoteManifestRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RemoteManifestsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RemoteManifestsTable,
      RemoteManifestRecord,
      $$RemoteManifestsTableFilterComposer,
      $$RemoteManifestsTableOrderingComposer,
      $$RemoteManifestsTableAnnotationComposer,
      $$RemoteManifestsTableCreateCompanionBuilder,
      $$RemoteManifestsTableUpdateCompanionBuilder,
      (
        RemoteManifestRecord,
        BaseReferences<
          _$AppDatabase,
          $RemoteManifestsTable,
          RemoteManifestRecord
        >,
      ),
      RemoteManifestRecord,
      PrefetchHooks Function()
    >;
typedef $$ItemsTableCreateCompanionBuilder = ItemsCompanion Function({
  required String id,
  required String name,
  required String shortName,
  required String normalizedName,
  Value<double?> weight,
  Value<int?> width,
  Value<int?> height,
  Value<int?> basePrice,
  Value<int?> avg24hPrice,
  Value<int?> lastLowPrice,
  Value<double?> changeLast48hPercent,
  Value<DateTime?> priceObservedAt,
  Value<String?> iconLink,
  Value<String?> gridImageLink,
  Value<int?> minLevelForFlea,
  Value<bool?> fleaEligible,
  required String payload,
  Value<int> rowid,
});
typedef $$ItemsTableUpdateCompanionBuilder = ItemsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> shortName,
  Value<String> normalizedName,
  Value<double?> weight,
  Value<int?> width,
  Value<int?> height,
  Value<int?> basePrice,
  Value<int?> avg24hPrice,
  Value<int?> lastLowPrice,
  Value<double?> changeLast48hPercent,
  Value<DateTime?> priceObservedAt,
  Value<String?> iconLink,
  Value<String?> gridImageLink,
  Value<int?> minLevelForFlea,
  Value<bool?> fleaEligible,
  Value<String> payload,
  Value<int> rowid,
});

final class $$ItemsTableReferences
    extends BaseReferences<_$AppDatabase, $ItemsTable, Item> {
  $$ItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ItemTypesTable, List<ItemType>>
  _itemTypesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.itemTypes,
    aliasName: 'items__id__itemTypes__itemId',
  );

  $$ItemTypesTableProcessedTableManager get itemTypesRefs {
    final manager = $$ItemTypesTableTableManager(
      $_db,
      $_db.itemTypes,
    ).filter((f) => f.itemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_itemTypesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ItemCategoriesTable, List<ItemCategory>>
  _itemCategoriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.itemCategories,
    aliasName: 'items__id__itemCategories__itemId',
  );

  $$ItemCategoriesTableProcessedTableManager get itemCategoriesRefs {
    final manager = $$ItemCategoriesTableTableManager(
      $_db,
      $_db.itemCategories,
    ).filter((f) => f.itemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_itemCategoriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ItemsTableFilterComposer extends Composer<_$AppDatabase, $ItemsTable> {
  $$ItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shortName => $composableBuilder(
    column: $table.shortName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get basePrice => $composableBuilder(
    column: $table.basePrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get avg24hPrice => $composableBuilder(
    column: $table.avg24hPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastLowPrice => $composableBuilder(
    column: $table.lastLowPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get changeLast48hPercent => $composableBuilder(
    column: $table.changeLast48hPercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get priceObservedAt => $composableBuilder(
    column: $table.priceObservedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get iconLink => $composableBuilder(
    column: $table.iconLink,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gridImageLink => $composableBuilder(
    column: $table.gridImageLink,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minLevelForFlea => $composableBuilder(
    column: $table.minLevelForFlea,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get fleaEligible => $composableBuilder(
    column: $table.fleaEligible,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> itemTypesRefs(
    Expression<bool> Function($$ItemTypesTableFilterComposer f) f,
  ) {
    final $$ItemTypesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.itemTypes,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemTypesTableFilterComposer(
            $db: $db,
            $table: $db.itemTypes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> itemCategoriesRefs(
    Expression<bool> Function($$ItemCategoriesTableFilterComposer f) f,
  ) {
    final $$ItemCategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.itemCategories,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemCategoriesTableFilterComposer(
            $db: $db,
            $table: $db.itemCategories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $ItemsTable> {
  $$ItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shortName => $composableBuilder(
    column: $table.shortName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get basePrice => $composableBuilder(
    column: $table.basePrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get avg24hPrice => $composableBuilder(
    column: $table.avg24hPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastLowPrice => $composableBuilder(
    column: $table.lastLowPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get changeLast48hPercent => $composableBuilder(
    column: $table.changeLast48hPercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get priceObservedAt => $composableBuilder(
    column: $table.priceObservedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get iconLink => $composableBuilder(
    column: $table.iconLink,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gridImageLink => $composableBuilder(
    column: $table.gridImageLink,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minLevelForFlea => $composableBuilder(
    column: $table.minLevelForFlea,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get fleaEligible => $composableBuilder(
    column: $table.fleaEligible,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ItemsTable> {
  $$ItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get shortName =>
      $composableBuilder(column: $table.shortName, builder: (column) => column);

  GeneratedColumn<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => column,
  );

  GeneratedColumn<double> get weight =>
      $composableBuilder(column: $table.weight, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get basePrice =>
      $composableBuilder(column: $table.basePrice, builder: (column) => column);

  GeneratedColumn<int> get avg24hPrice => $composableBuilder(
    column: $table.avg24hPrice,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastLowPrice => $composableBuilder(
    column: $table.lastLowPrice,
    builder: (column) => column,
  );

  GeneratedColumn<double> get changeLast48hPercent => $composableBuilder(
    column: $table.changeLast48hPercent,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get priceObservedAt => $composableBuilder(
    column: $table.priceObservedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get iconLink =>
      $composableBuilder(column: $table.iconLink, builder: (column) => column);

  GeneratedColumn<String> get gridImageLink => $composableBuilder(
    column: $table.gridImageLink,
    builder: (column) => column,
  );

  GeneratedColumn<int> get minLevelForFlea => $composableBuilder(
    column: $table.minLevelForFlea,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get fleaEligible => $composableBuilder(
    column: $table.fleaEligible,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  Expression<T> itemTypesRefs<T extends Object>(
    Expression<T> Function($$ItemTypesTableAnnotationComposer a) f,
  ) {
    final $$ItemTypesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.itemTypes,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemTypesTableAnnotationComposer(
            $db: $db,
            $table: $db.itemTypes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> itemCategoriesRefs<T extends Object>(
    Expression<T> Function($$ItemCategoriesTableAnnotationComposer a) f,
  ) {
    final $$ItemCategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.itemCategories,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemCategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.itemCategories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ItemsTable,
          Item,
          $$ItemsTableFilterComposer,
          $$ItemsTableOrderingComposer,
          $$ItemsTableAnnotationComposer,
          $$ItemsTableCreateCompanionBuilder,
          $$ItemsTableUpdateCompanionBuilder,
          (Item, $$ItemsTableReferences),
          Item,
          PrefetchHooks Function({bool itemTypesRefs, bool itemCategoriesRefs})
        > {
  $$ItemsTableTableManager(_$AppDatabase db, $ItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> shortName = const Value.absent(),
                Value<String> normalizedName = const Value.absent(),
                Value<double?> weight = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> basePrice = const Value.absent(),
                Value<int?> avg24hPrice = const Value.absent(),
                Value<int?> lastLowPrice = const Value.absent(),
                Value<double?> changeLast48hPercent = const Value.absent(),
                Value<DateTime?> priceObservedAt = const Value.absent(),
                Value<String?> iconLink = const Value.absent(),
                Value<String?> gridImageLink = const Value.absent(),
                Value<int?> minLevelForFlea = const Value.absent(),
                Value<bool?> fleaEligible = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ItemsCompanion(
                id: id,
                name: name,
                shortName: shortName,
                normalizedName: normalizedName,
                weight: weight,
                width: width,
                height: height,
                basePrice: basePrice,
                avg24hPrice: avg24hPrice,
                lastLowPrice: lastLowPrice,
                changeLast48hPercent: changeLast48hPercent,
                priceObservedAt: priceObservedAt,
                iconLink: iconLink,
                gridImageLink: gridImageLink,
                minLevelForFlea: minLevelForFlea,
                fleaEligible: fleaEligible,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String shortName,
                required String normalizedName,
                Value<double?> weight = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> basePrice = const Value.absent(),
                Value<int?> avg24hPrice = const Value.absent(),
                Value<int?> lastLowPrice = const Value.absent(),
                Value<double?> changeLast48hPercent = const Value.absent(),
                Value<DateTime?> priceObservedAt = const Value.absent(),
                Value<String?> iconLink = const Value.absent(),
                Value<String?> gridImageLink = const Value.absent(),
                Value<int?> minLevelForFlea = const Value.absent(),
                Value<bool?> fleaEligible = const Value.absent(),
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => ItemsCompanion.insert(
                id: id,
                name: name,
                shortName: shortName,
                normalizedName: normalizedName,
                weight: weight,
                width: width,
                height: height,
                basePrice: basePrice,
                avg24hPrice: avg24hPrice,
                lastLowPrice: lastLowPrice,
                changeLast48hPercent: changeLast48hPercent,
                priceObservedAt: priceObservedAt,
                iconLink: iconLink,
                gridImageLink: gridImageLink,
                minLevelForFlea: minLevelForFlea,
                fleaEligible: fleaEligible,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ItemsTable, Item>(table),
                  $$ItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({itemTypesRefs = false, itemCategoriesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (itemTypesRefs) db.itemTypes,
                    if (itemCategoriesRefs) db.itemCategories,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (itemTypesRefs)
                        await $_getPrefetchedDataByColumns<
                          Item,
                          $ItemsTable,
                          ItemType,
                          $ItemTypesTable
                        >(
                          currentTable: table,
                          referencedTable: $$ItemsTableReferences
                              ._itemTypesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).itemTypesRefs,
                          currentColumn: 'id',
                          referencedColumn: 'itemId',
                          typedResults: items,
                        ),
                      if (itemCategoriesRefs)
                        await $_getPrefetchedDataByColumns<
                          Item,
                          $ItemsTable,
                          ItemCategory,
                          $ItemCategoriesTable
                        >(
                          currentTable: table,
                          referencedTable: $$ItemsTableReferences
                              ._itemCategoriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).itemCategoriesRefs,
                          currentColumn: 'id',
                          referencedColumn: 'itemId',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ItemsTable,
      Item,
      $$ItemsTableFilterComposer,
      $$ItemsTableOrderingComposer,
      $$ItemsTableAnnotationComposer,
      $$ItemsTableCreateCompanionBuilder,
      $$ItemsTableUpdateCompanionBuilder,
      (Item, $$ItemsTableReferences),
      Item,
      PrefetchHooks Function({bool itemTypesRefs, bool itemCategoriesRefs})
    >;
typedef $$ItemTypesTableCreateCompanionBuilder = ItemTypesCompanion Function({
  required String itemId,
  required String type,
  Value<int> rowid,
});
typedef $$ItemTypesTableUpdateCompanionBuilder = ItemTypesCompanion Function({
  Value<String> itemId,
  Value<String> type,
  Value<int> rowid,
});

final class $$ItemTypesTableReferences
    extends BaseReferences<_$AppDatabase, $ItemTypesTable, ItemType> {
  $$ItemTypesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ItemsTable _itemIdTable(_$AppDatabase db) =>
      db.items.createAlias('itemTypes__itemId__items__id');

  $$ItemsTableProcessedTableManager get itemId {
    final $_column = $_itemColumn<String>('itemId')!;

    final manager = $$ItemsTableTableManager(
      $_db,
      $_db.items,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_itemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ItemTypesTableFilterComposer
    extends Composer<_$AppDatabase, $ItemTypesTable> {
  $$ItemTypesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  $$ItemsTableFilterComposer get itemId {
    final $$ItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableFilterComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ItemTypesTableOrderingComposer
    extends Composer<_$AppDatabase, $ItemTypesTable> {
  $$ItemTypesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  $$ItemsTableOrderingComposer get itemId {
    final $$ItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableOrderingComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ItemTypesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ItemTypesTable> {
  $$ItemTypesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  $$ItemsTableAnnotationComposer get itemId {
    final $$ItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ItemTypesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ItemTypesTable,
          ItemType,
          $$ItemTypesTableFilterComposer,
          $$ItemTypesTableOrderingComposer,
          $$ItemTypesTableAnnotationComposer,
          $$ItemTypesTableCreateCompanionBuilder,
          $$ItemTypesTableUpdateCompanionBuilder,
          (ItemType, $$ItemTypesTableReferences),
          ItemType,
          PrefetchHooks Function({bool itemId})
        > {
  $$ItemTypesTableTableManager(_$AppDatabase db, $ItemTypesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ItemTypesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ItemTypesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ItemTypesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> itemId = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => ItemTypesCompanion(itemId: itemId, type: type, rowid: rowid),
          createCompanionCallback:
              ({
                required String itemId,
                required String type,
                Value<int> rowid = const Value.absent(),
              }) => ItemTypesCompanion.insert(
                itemId: itemId,
                type: type,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ItemTypesTable, ItemType>(table),
                  $$ItemTypesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({itemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (itemId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.itemId,
                        referencedTable: $$ItemTypesTableReferences
                            ._itemIdTable(db),
                        referencedColumn: $$ItemTypesTableReferences
                            ._itemIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ItemTypesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ItemTypesTable,
      ItemType,
      $$ItemTypesTableFilterComposer,
      $$ItemTypesTableOrderingComposer,
      $$ItemTypesTableAnnotationComposer,
      $$ItemTypesTableCreateCompanionBuilder,
      $$ItemTypesTableUpdateCompanionBuilder,
      (ItemType, $$ItemTypesTableReferences),
      ItemType,
      PrefetchHooks Function({bool itemId})
    >;
typedef $$ItemCategoriesTableCreateCompanionBuilder =
    ItemCategoriesCompanion Function({
      required String itemId,
      required String categoryId,
      required String categoryKind,
      Value<int> rowid,
    });
typedef $$ItemCategoriesTableUpdateCompanionBuilder =
    ItemCategoriesCompanion Function({
      Value<String> itemId,
      Value<String> categoryId,
      Value<String> categoryKind,
      Value<int> rowid,
    });

final class $$ItemCategoriesTableReferences
    extends BaseReferences<_$AppDatabase, $ItemCategoriesTable, ItemCategory> {
  $$ItemCategoriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ItemsTable _itemIdTable(_$AppDatabase db) =>
      db.items.createAlias('itemCategories__itemId__items__id');

  $$ItemsTableProcessedTableManager get itemId {
    final $_column = $_itemColumn<String>('itemId')!;

    final manager = $$ItemsTableTableManager(
      $_db,
      $_db.items,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_itemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ItemCategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $ItemCategoriesTable> {
  $$ItemCategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryKind => $composableBuilder(
    column: $table.categoryKind,
    builder: (column) => ColumnFilters(column),
  );

  $$ItemsTableFilterComposer get itemId {
    final $$ItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableFilterComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ItemCategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $ItemCategoriesTable> {
  $$ItemCategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryKind => $composableBuilder(
    column: $table.categoryKind,
    builder: (column) => ColumnOrderings(column),
  );

  $$ItemsTableOrderingComposer get itemId {
    final $$ItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableOrderingComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ItemCategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ItemCategoriesTable> {
  $$ItemCategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get categoryKind => $composableBuilder(
    column: $table.categoryKind,
    builder: (column) => column,
  );

  $$ItemsTableAnnotationComposer get itemId {
    final $$ItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ItemCategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ItemCategoriesTable,
          ItemCategory,
          $$ItemCategoriesTableFilterComposer,
          $$ItemCategoriesTableOrderingComposer,
          $$ItemCategoriesTableAnnotationComposer,
          $$ItemCategoriesTableCreateCompanionBuilder,
          $$ItemCategoriesTableUpdateCompanionBuilder,
          (ItemCategory, $$ItemCategoriesTableReferences),
          ItemCategory,
          PrefetchHooks Function({bool itemId})
        > {
  $$ItemCategoriesTableTableManager(
    _$AppDatabase db,
    $ItemCategoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ItemCategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ItemCategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ItemCategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> itemId = const Value.absent(),
                Value<String> categoryId = const Value.absent(),
                Value<String> categoryKind = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ItemCategoriesCompanion(
                itemId: itemId,
                categoryId: categoryId,
                categoryKind: categoryKind,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String itemId,
                required String categoryId,
                required String categoryKind,
                Value<int> rowid = const Value.absent(),
              }) => ItemCategoriesCompanion.insert(
                itemId: itemId,
                categoryId: categoryId,
                categoryKind: categoryKind,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ItemCategoriesTable, ItemCategory>(table),
                  $$ItemCategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({itemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (itemId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.itemId,
                        referencedTable: $$ItemCategoriesTableReferences
                            ._itemIdTable(db),
                        referencedColumn: $$ItemCategoriesTableReferences
                            ._itemIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ItemCategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ItemCategoriesTable,
      ItemCategory,
      $$ItemCategoriesTableFilterComposer,
      $$ItemCategoriesTableOrderingComposer,
      $$ItemCategoriesTableAnnotationComposer,
      $$ItemCategoriesTableCreateCompanionBuilder,
      $$ItemCategoriesTableUpdateCompanionBuilder,
      (ItemCategory, $$ItemCategoriesTableReferences),
      ItemCategory,
      PrefetchHooks Function({bool itemId})
    >;
typedef $$TasksTableCreateCompanionBuilder = TasksCompanion Function({
  required String id,
  required String name,
  Value<String?> traderId,
  Value<String?> mapId,
  Value<int?> minPlayerLevel,
  Value<int?> experience,
  Value<bool> kappaRequired,
  required String payload,
  Value<int> rowid,
});
typedef $$TasksTableUpdateCompanionBuilder = TasksCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String?> traderId,
  Value<String?> mapId,
  Value<int?> minPlayerLevel,
  Value<int?> experience,
  Value<bool> kappaRequired,
  Value<String> payload,
  Value<int> rowid,
});

final class $$TasksTableReferences
    extends BaseReferences<_$AppDatabase, $TasksTable, Task> {
  $$TasksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TaskObjectivesTable, List<TaskObjective>>
  _taskObjectivesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.taskObjectives,
    aliasName: 'tasks__id__taskObjectives__taskId',
  );

  $$TaskObjectivesTableProcessedTableManager get taskObjectivesRefs {
    final manager = $$TaskObjectivesTableTableManager(
      $_db,
      $_db.taskObjectives,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_taskObjectivesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TasksTableFilterComposer extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get traderId => $composableBuilder(
    column: $table.traderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mapId => $composableBuilder(
    column: $table.mapId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minPlayerLevel => $composableBuilder(
    column: $table.minPlayerLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get experience => $composableBuilder(
    column: $table.experience,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get kappaRequired => $composableBuilder(
    column: $table.kappaRequired,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> taskObjectivesRefs(
    Expression<bool> Function($$TaskObjectivesTableFilterComposer f) f,
  ) {
    final $$TaskObjectivesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskObjectives,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskObjectivesTableFilterComposer(
            $db: $db,
            $table: $db.taskObjectives,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TasksTableOrderingComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get traderId => $composableBuilder(
    column: $table.traderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mapId => $composableBuilder(
    column: $table.mapId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minPlayerLevel => $composableBuilder(
    column: $table.minPlayerLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get experience => $composableBuilder(
    column: $table.experience,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get kappaRequired => $composableBuilder(
    column: $table.kappaRequired,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get traderId =>
      $composableBuilder(column: $table.traderId, builder: (column) => column);

  GeneratedColumn<String> get mapId =>
      $composableBuilder(column: $table.mapId, builder: (column) => column);

  GeneratedColumn<int> get minPlayerLevel => $composableBuilder(
    column: $table.minPlayerLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get experience => $composableBuilder(
    column: $table.experience,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get kappaRequired => $composableBuilder(
    column: $table.kappaRequired,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  Expression<T> taskObjectivesRefs<T extends Object>(
    Expression<T> Function($$TaskObjectivesTableAnnotationComposer a) f,
  ) {
    final $$TaskObjectivesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskObjectives,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskObjectivesTableAnnotationComposer(
            $db: $db,
            $table: $db.taskObjectives,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TasksTable,
          Task,
          $$TasksTableFilterComposer,
          $$TasksTableOrderingComposer,
          $$TasksTableAnnotationComposer,
          $$TasksTableCreateCompanionBuilder,
          $$TasksTableUpdateCompanionBuilder,
          (Task, $$TasksTableReferences),
          Task,
          PrefetchHooks Function({bool taskObjectivesRefs})
        > {
  $$TasksTableTableManager(_$AppDatabase db, $TasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> traderId = const Value.absent(),
                Value<String?> mapId = const Value.absent(),
                Value<int?> minPlayerLevel = const Value.absent(),
                Value<int?> experience = const Value.absent(),
                Value<bool> kappaRequired = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion(
                id: id,
                name: name,
                traderId: traderId,
                mapId: mapId,
                minPlayerLevel: minPlayerLevel,
                experience: experience,
                kappaRequired: kappaRequired,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> traderId = const Value.absent(),
                Value<String?> mapId = const Value.absent(),
                Value<int?> minPlayerLevel = const Value.absent(),
                Value<int?> experience = const Value.absent(),
                Value<bool> kappaRequired = const Value.absent(),
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion.insert(
                id: id,
                name: name,
                traderId: traderId,
                mapId: mapId,
                minPlayerLevel: minPlayerLevel,
                experience: experience,
                kappaRequired: kappaRequired,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TasksTable, Task>(table),
                  $$TasksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({taskObjectivesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (taskObjectivesRefs) db.taskObjectives,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (taskObjectivesRefs)
                    await $_getPrefetchedDataByColumns<
                      Task,
                      $TasksTable,
                      TaskObjective,
                      $TaskObjectivesTable
                    >(
                      currentTable: table,
                      referencedTable: $$TasksTableReferences
                          ._taskObjectivesRefsTable(db),
                      managerFromTypedResult: (p0) => $$TasksTableReferences(
                        db,
                        table,
                        p0,
                      ).taskObjectivesRefs,
                      currentColumn: 'id',
                      referencedColumn: 'taskId',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TasksTable,
      Task,
      $$TasksTableFilterComposer,
      $$TasksTableOrderingComposer,
      $$TasksTableAnnotationComposer,
      $$TasksTableCreateCompanionBuilder,
      $$TasksTableUpdateCompanionBuilder,
      (Task, $$TasksTableReferences),
      Task,
      PrefetchHooks Function({bool taskObjectivesRefs})
    >;
typedef $$TaskObjectivesTableCreateCompanionBuilder =
    TaskObjectivesCompanion Function({
      required String id,
      required String taskId,
      required String type,
      Value<String> description,
      Value<int?> count,
      required String payload,
      Value<int> rowid,
    });
typedef $$TaskObjectivesTableUpdateCompanionBuilder =
    TaskObjectivesCompanion Function({
      Value<String> id,
      Value<String> taskId,
      Value<String> type,
      Value<String> description,
      Value<int?> count,
      Value<String> payload,
      Value<int> rowid,
    });

final class $$TaskObjectivesTableReferences
    extends BaseReferences<_$AppDatabase, $TaskObjectivesTable, TaskObjective> {
  $$TaskObjectivesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TasksTable _taskIdTable(_$AppDatabase db) =>
      db.tasks.createAlias('taskObjectives__taskId__tasks__id');

  $$TasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<String>('taskId')!;

    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TaskObjectivesTableFilterComposer
    extends Composer<_$AppDatabase, $TaskObjectivesTable> {
  $$TaskObjectivesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  $$TasksTableFilterComposer get taskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskObjectivesTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskObjectivesTable> {
  $$TaskObjectivesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  $$TasksTableOrderingComposer get taskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskObjectivesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskObjectivesTable> {
  $$TaskObjectivesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get count =>
      $composableBuilder(column: $table.count, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  $$TasksTableAnnotationComposer get taskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskObjectivesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TaskObjectivesTable,
          TaskObjective,
          $$TaskObjectivesTableFilterComposer,
          $$TaskObjectivesTableOrderingComposer,
          $$TaskObjectivesTableAnnotationComposer,
          $$TaskObjectivesTableCreateCompanionBuilder,
          $$TaskObjectivesTableUpdateCompanionBuilder,
          (TaskObjective, $$TaskObjectivesTableReferences),
          TaskObjective,
          PrefetchHooks Function({bool taskId})
        > {
  $$TaskObjectivesTableTableManager(
    _$AppDatabase db,
    $TaskObjectivesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskObjectivesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskObjectivesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskObjectivesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<int?> count = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskObjectivesCompanion(
                id: id,
                taskId: taskId,
                type: type,
                description: description,
                count: count,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String taskId,
                required String type,
                Value<String> description = const Value.absent(),
                Value<int?> count = const Value.absent(),
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => TaskObjectivesCompanion.insert(
                id: id,
                taskId: taskId,
                type: type,
                description: description,
                count: count,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TaskObjectivesTable, TaskObjective>(table),
                  $$TaskObjectivesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({taskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (taskId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.taskId,
                        referencedTable: $$TaskObjectivesTableReferences
                            ._taskIdTable(db),
                        referencedColumn: $$TaskObjectivesTableReferences
                            ._taskIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TaskObjectivesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TaskObjectivesTable,
      TaskObjective,
      $$TaskObjectivesTableFilterComposer,
      $$TaskObjectivesTableOrderingComposer,
      $$TaskObjectivesTableAnnotationComposer,
      $$TaskObjectivesTableCreateCompanionBuilder,
      $$TaskObjectivesTableUpdateCompanionBuilder,
      (TaskObjective, $$TaskObjectivesTableReferences),
      TaskObjective,
      PrefetchHooks Function({bool taskId})
    >;
typedef $$TradersTableCreateCompanionBuilder = TradersCompanion Function({
  required String id,
  required String name,
  required String normalizedName,
  required String payload,
  Value<int> rowid,
});
typedef $$TradersTableUpdateCompanionBuilder = TradersCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> normalizedName,
  Value<String> payload,
  Value<int> rowid,
});

class $$TradersTableFilterComposer
    extends Composer<_$AppDatabase, $TradersTable> {
  $$TradersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TradersTableOrderingComposer
    extends Composer<_$AppDatabase, $TradersTable> {
  $$TradersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TradersTableAnnotationComposer
    extends Composer<_$AppDatabase, $TradersTable> {
  $$TradersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$TradersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TradersTable,
          Trader,
          $$TradersTableFilterComposer,
          $$TradersTableOrderingComposer,
          $$TradersTableAnnotationComposer,
          $$TradersTableCreateCompanionBuilder,
          $$TradersTableUpdateCompanionBuilder,
          (Trader, BaseReferences<_$AppDatabase, $TradersTable, Trader>),
          Trader,
          PrefetchHooks Function()
        > {
  $$TradersTableTableManager(_$AppDatabase db, $TradersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TradersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TradersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TradersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> normalizedName = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TradersCompanion(
                id: id,
                name: name,
                normalizedName: normalizedName,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String normalizedName,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => TradersCompanion.insert(
                id: id,
                name: name,
                normalizedName: normalizedName,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TradersTable, Trader>(table),
                  BaseReferences<_$AppDatabase, $TradersTable, Trader>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TradersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TradersTable,
      Trader,
      $$TradersTableFilterComposer,
      $$TradersTableOrderingComposer,
      $$TradersTableAnnotationComposer,
      $$TradersTableCreateCompanionBuilder,
      $$TradersTableUpdateCompanionBuilder,
      (Trader, BaseReferences<_$AppDatabase, $TradersTable, Trader>),
      Trader,
      PrefetchHooks Function()
    >;
typedef $$HideoutStationsTableCreateCompanionBuilder =
    HideoutStationsCompanion Function({
      required String id,
      required String name,
      required String payload,
      Value<int> rowid,
    });
typedef $$HideoutStationsTableUpdateCompanionBuilder =
    HideoutStationsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> payload,
      Value<int> rowid,
    });

class $$HideoutStationsTableFilterComposer
    extends Composer<_$AppDatabase, $HideoutStationsTable> {
  $$HideoutStationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HideoutStationsTableOrderingComposer
    extends Composer<_$AppDatabase, $HideoutStationsTable> {
  $$HideoutStationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HideoutStationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HideoutStationsTable> {
  $$HideoutStationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$HideoutStationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HideoutStationsTable,
          HideoutStation,
          $$HideoutStationsTableFilterComposer,
          $$HideoutStationsTableOrderingComposer,
          $$HideoutStationsTableAnnotationComposer,
          $$HideoutStationsTableCreateCompanionBuilder,
          $$HideoutStationsTableUpdateCompanionBuilder,
          (
            HideoutStation,
            BaseReferences<
              _$AppDatabase,
              $HideoutStationsTable,
              HideoutStation
            >,
          ),
          HideoutStation,
          PrefetchHooks Function()
        > {
  $$HideoutStationsTableTableManager(
    _$AppDatabase db,
    $HideoutStationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HideoutStationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HideoutStationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HideoutStationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HideoutStationsCompanion(
                id: id,
                name: name,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => HideoutStationsCompanion.insert(
                id: id,
                name: name,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$HideoutStationsTable, HideoutStation>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $HideoutStationsTable,
                    HideoutStation
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HideoutStationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HideoutStationsTable,
      HideoutStation,
      $$HideoutStationsTableFilterComposer,
      $$HideoutStationsTableOrderingComposer,
      $$HideoutStationsTableAnnotationComposer,
      $$HideoutStationsTableCreateCompanionBuilder,
      $$HideoutStationsTableUpdateCompanionBuilder,
      (
        HideoutStation,
        BaseReferences<_$AppDatabase, $HideoutStationsTable, HideoutStation>,
      ),
      HideoutStation,
      PrefetchHooks Function()
    >;
typedef $$CraftsTableCreateCompanionBuilder = CraftsCompanion Function({
  required String id,
  required String stationId,
  required String productItemId,
  required String payload,
  Value<int> rowid,
});
typedef $$CraftsTableUpdateCompanionBuilder = CraftsCompanion Function({
  Value<String> id,
  Value<String> stationId,
  Value<String> productItemId,
  Value<String> payload,
  Value<int> rowid,
});

class $$CraftsTableFilterComposer
    extends Composer<_$AppDatabase, $CraftsTable> {
  $$CraftsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productItemId => $composableBuilder(
    column: $table.productItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CraftsTableOrderingComposer
    extends Composer<_$AppDatabase, $CraftsTable> {
  $$CraftsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productItemId => $composableBuilder(
    column: $table.productItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CraftsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CraftsTable> {
  $$CraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get stationId =>
      $composableBuilder(column: $table.stationId, builder: (column) => column);

  GeneratedColumn<String> get productItemId => $composableBuilder(
    column: $table.productItemId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$CraftsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CraftsTable,
          Craft,
          $$CraftsTableFilterComposer,
          $$CraftsTableOrderingComposer,
          $$CraftsTableAnnotationComposer,
          $$CraftsTableCreateCompanionBuilder,
          $$CraftsTableUpdateCompanionBuilder,
          (Craft, BaseReferences<_$AppDatabase, $CraftsTable, Craft>),
          Craft,
          PrefetchHooks Function()
        > {
  $$CraftsTableTableManager(_$AppDatabase db, $CraftsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CraftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CraftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> stationId = const Value.absent(),
                Value<String> productItemId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CraftsCompanion(
                id: id,
                stationId: stationId,
                productItemId: productItemId,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String stationId,
                required String productItemId,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => CraftsCompanion.insert(
                id: id,
                stationId: stationId,
                productItemId: productItemId,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CraftsTable, Craft>(table),
                  BaseReferences<_$AppDatabase, $CraftsTable, Craft>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CraftsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CraftsTable,
      Craft,
      $$CraftsTableFilterComposer,
      $$CraftsTableOrderingComposer,
      $$CraftsTableAnnotationComposer,
      $$CraftsTableCreateCompanionBuilder,
      $$CraftsTableUpdateCompanionBuilder,
      (Craft, BaseReferences<_$AppDatabase, $CraftsTable, Craft>),
      Craft,
      PrefetchHooks Function()
    >;
typedef $$BartersTableCreateCompanionBuilder = BartersCompanion Function({
  required String id,
  required String payload,
  Value<int> rowid,
});
typedef $$BartersTableUpdateCompanionBuilder = BartersCompanion Function({
  Value<String> id,
  Value<String> payload,
  Value<int> rowid,
});

class $$BartersTableFilterComposer
    extends Composer<_$AppDatabase, $BartersTable> {
  $$BartersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BartersTableOrderingComposer
    extends Composer<_$AppDatabase, $BartersTable> {
  $$BartersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BartersTableAnnotationComposer
    extends Composer<_$AppDatabase, $BartersTable> {
  $$BartersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$BartersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BartersTable,
          Barter,
          $$BartersTableFilterComposer,
          $$BartersTableOrderingComposer,
          $$BartersTableAnnotationComposer,
          $$BartersTableCreateCompanionBuilder,
          $$BartersTableUpdateCompanionBuilder,
          (Barter, BaseReferences<_$AppDatabase, $BartersTable, Barter>),
          Barter,
          PrefetchHooks Function()
        > {
  $$BartersTableTableManager(_$AppDatabase db, $BartersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BartersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BartersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BartersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => BartersCompanion(id: id, payload: payload, rowid: rowid),
          createCompanionCallback: ({
            required String id,
            required String payload,
            Value<int> rowid = const Value.absent(),
          }) => BartersCompanion.insert(id: id, payload: payload, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BartersTable, Barter>(table),
                  BaseReferences<_$AppDatabase, $BartersTable, Barter>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BartersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BartersTable,
      Barter,
      $$BartersTableFilterComposer,
      $$BartersTableOrderingComposer,
      $$BartersTableAnnotationComposer,
      $$BartersTableCreateCompanionBuilder,
      $$BartersTableUpdateCompanionBuilder,
      (Barter, BaseReferences<_$AppDatabase, $BartersTable, Barter>),
      Barter,
      PrefetchHooks Function()
    >;
typedef $$MapsTableCreateCompanionBuilder = MapsCompanion Function({
  required String id,
  required String name,
  required String normalizedName,
  required String payload,
  Value<int> rowid,
});
typedef $$MapsTableUpdateCompanionBuilder = MapsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> normalizedName,
  Value<String> payload,
  Value<int> rowid,
});

class $$MapsTableFilterComposer extends Composer<_$AppDatabase, $MapsTable> {
  $$MapsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MapsTableOrderingComposer extends Composer<_$AppDatabase, $MapsTable> {
  $$MapsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MapsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MapsTable> {
  $$MapsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$MapsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MapsTable,
          TarkovMap,
          $$MapsTableFilterComposer,
          $$MapsTableOrderingComposer,
          $$MapsTableAnnotationComposer,
          $$MapsTableCreateCompanionBuilder,
          $$MapsTableUpdateCompanionBuilder,
          (TarkovMap, BaseReferences<_$AppDatabase, $MapsTable, TarkovMap>),
          TarkovMap,
          PrefetchHooks Function()
        > {
  $$MapsTableTableManager(_$AppDatabase db, $MapsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MapsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MapsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MapsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> normalizedName = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MapsCompanion(
                id: id,
                name: name,
                normalizedName: normalizedName,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String normalizedName,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => MapsCompanion.insert(
                id: id,
                name: name,
                normalizedName: normalizedName,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MapsTable, TarkovMap>(table),
                  BaseReferences<_$AppDatabase, $MapsTable, TarkovMap>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MapsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MapsTable,
      TarkovMap,
      $$MapsTableFilterComposer,
      $$MapsTableOrderingComposer,
      $$MapsTableAnnotationComposer,
      $$MapsTableCreateCompanionBuilder,
      $$MapsTableUpdateCompanionBuilder,
      (TarkovMap, BaseReferences<_$AppDatabase, $MapsTable, TarkovMap>),
      TarkovMap,
      PrefetchHooks Function()
    >;
typedef $$GameRecordsTableCreateCompanionBuilder =
    GameRecordsCompanion Function({
      required String kind,
      required String id,
      required String payload,
      Value<int> rowid,
    });
typedef $$GameRecordsTableUpdateCompanionBuilder =
    GameRecordsCompanion Function({
      Value<String> kind,
      Value<String> id,
      Value<String> payload,
      Value<int> rowid,
    });

class $$GameRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $GameRecordsTable> {
  $$GameRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GameRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $GameRecordsTable> {
  $$GameRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GameRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GameRecordsTable> {
  $$GameRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$GameRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GameRecordsTable,
          GameRecord,
          $$GameRecordsTableFilterComposer,
          $$GameRecordsTableOrderingComposer,
          $$GameRecordsTableAnnotationComposer,
          $$GameRecordsTableCreateCompanionBuilder,
          $$GameRecordsTableUpdateCompanionBuilder,
          (
            GameRecord,
            BaseReferences<_$AppDatabase, $GameRecordsTable, GameRecord>,
          ),
          GameRecord,
          PrefetchHooks Function()
        > {
  $$GameRecordsTableTableManager(_$AppDatabase db, $GameRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GameRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GameRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GameRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> kind = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GameRecordsCompanion(
                kind: kind,
                id: id,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String kind,
                required String id,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => GameRecordsCompanion.insert(
                kind: kind,
                id: id,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GameRecordsTable, GameRecord>(table),
                  BaseReferences<_$AppDatabase, $GameRecordsTable, GameRecord>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GameRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GameRecordsTable,
      GameRecord,
      $$GameRecordsTableFilterComposer,
      $$GameRecordsTableOrderingComposer,
      $$GameRecordsTableAnnotationComposer,
      $$GameRecordsTableCreateCompanionBuilder,
      $$GameRecordsTableUpdateCompanionBuilder,
      (
        GameRecord,
        BaseReferences<_$AppDatabase, $GameRecordsTable, GameRecord>,
      ),
      GameRecord,
      PrefetchHooks Function()
    >;
typedef $$PriceHistoryTableCreateCompanionBuilder =
    PriceHistoryCompanion Function({
      required String itemId,
      required DateTime observedAt,
      required int price,
      Value<int?> priceMin,
      Value<int> rowid,
    });
typedef $$PriceHistoryTableUpdateCompanionBuilder =
    PriceHistoryCompanion Function({
      Value<String> itemId,
      Value<DateTime> observedAt,
      Value<int> price,
      Value<int?> priceMin,
      Value<int> rowid,
    });

class $$PriceHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $PriceHistoryTable> {
  $$PriceHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priceMin => $composableBuilder(
    column: $table.priceMin,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PriceHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $PriceHistoryTable> {
  $$PriceHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priceMin => $composableBuilder(
    column: $table.priceMin,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PriceHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $PriceHistoryTable> {
  $$PriceHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<int> get priceMin =>
      $composableBuilder(column: $table.priceMin, builder: (column) => column);
}

class $$PriceHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PriceHistoryTable,
          PriceHistoryEntry,
          $$PriceHistoryTableFilterComposer,
          $$PriceHistoryTableOrderingComposer,
          $$PriceHistoryTableAnnotationComposer,
          $$PriceHistoryTableCreateCompanionBuilder,
          $$PriceHistoryTableUpdateCompanionBuilder,
          (
            PriceHistoryEntry,
            BaseReferences<
              _$AppDatabase,
              $PriceHistoryTable,
              PriceHistoryEntry
            >,
          ),
          PriceHistoryEntry,
          PrefetchHooks Function()
        > {
  $$PriceHistoryTableTableManager(_$AppDatabase db, $PriceHistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PriceHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PriceHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PriceHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> itemId = const Value.absent(),
                Value<DateTime> observedAt = const Value.absent(),
                Value<int> price = const Value.absent(),
                Value<int?> priceMin = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PriceHistoryCompanion(
                itemId: itemId,
                observedAt: observedAt,
                price: price,
                priceMin: priceMin,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String itemId,
                required DateTime observedAt,
                required int price,
                Value<int?> priceMin = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PriceHistoryCompanion.insert(
                itemId: itemId,
                observedAt: observedAt,
                price: price,
                priceMin: priceMin,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PriceHistoryTable, PriceHistoryEntry>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PriceHistoryTable,
                    PriceHistoryEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PriceHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PriceHistoryTable,
      PriceHistoryEntry,
      $$PriceHistoryTableFilterComposer,
      $$PriceHistoryTableOrderingComposer,
      $$PriceHistoryTableAnnotationComposer,
      $$PriceHistoryTableCreateCompanionBuilder,
      $$PriceHistoryTableUpdateCompanionBuilder,
      (
        PriceHistoryEntry,
        BaseReferences<_$AppDatabase, $PriceHistoryTable, PriceHistoryEntry>,
      ),
      PriceHistoryEntry,
      PrefetchHooks Function()
    >;
typedef $$ProfilesTableCreateCompanionBuilder = ProfilesCompanion Function({
  required String id,
  required String gameMode,
  Value<int> playerLevel,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$ProfilesTableUpdateCompanionBuilder = ProfilesCompanion Function({
  Value<String> id,
  Value<String> gameMode,
  Value<int> playerLevel,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

final class $$ProfilesTableReferences
    extends BaseReferences<_$AppDatabase, $ProfilesTable, Profile> {
  $$ProfilesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$QuestProgressTable, List<QuestProgressEntry>>
  _questProgressRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.questProgress,
    aliasName: 'profiles__id__questProgress__profileId',
  );

  $$QuestProgressTableProcessedTableManager get questProgressRefs {
    final manager = $$QuestProgressTableTableManager(
      $_db,
      $_db.questProgress,
    ).filter((f) => f.profileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_questProgressRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ObjectiveProgressTable,
    List<ObjectiveProgressEntry>
  >
  _objectiveProgressRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.objectiveProgress,
        aliasName: 'profiles__id__objectiveProgress__profileId',
      );

  $$ObjectiveProgressTableProcessedTableManager get objectiveProgressRefs {
    final manager = $$ObjectiveProgressTableTableManager(
      $_db,
      $_db.objectiveProgress,
    ).filter((f) => f.profileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _objectiveProgressRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gameMode => $composableBuilder(
    column: $table.gameMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playerLevel => $composableBuilder(
    column: $table.playerLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> questProgressRefs(
    Expression<bool> Function($$QuestProgressTableFilterComposer f) f,
  ) {
    final $$QuestProgressTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.questProgress,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$QuestProgressTableFilterComposer(
            $db: $db,
            $table: $db.questProgress,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> objectiveProgressRefs(
    Expression<bool> Function($$ObjectiveProgressTableFilterComposer f) f,
  ) {
    final $$ObjectiveProgressTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.objectiveProgress,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObjectiveProgressTableFilterComposer(
            $db: $db,
            $table: $db.objectiveProgress,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gameMode => $composableBuilder(
    column: $table.gameMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playerLevel => $composableBuilder(
    column: $table.playerLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get gameMode =>
      $composableBuilder(column: $table.gameMode, builder: (column) => column);

  GeneratedColumn<int> get playerLevel => $composableBuilder(
    column: $table.playerLevel,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> questProgressRefs<T extends Object>(
    Expression<T> Function($$QuestProgressTableAnnotationComposer a) f,
  ) {
    final $$QuestProgressTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.questProgress,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$QuestProgressTableAnnotationComposer(
            $db: $db,
            $table: $db.questProgress,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> objectiveProgressRefs<T extends Object>(
    Expression<T> Function($$ObjectiveProgressTableAnnotationComposer a) f,
  ) {
    final $$ObjectiveProgressTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.objectiveProgress,
          getReferencedColumn: (t) => t.profileId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ObjectiveProgressTableAnnotationComposer(
                $db: $db,
                $table: $db.objectiveProgress,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProfilesTable,
          Profile,
          $$ProfilesTableFilterComposer,
          $$ProfilesTableOrderingComposer,
          $$ProfilesTableAnnotationComposer,
          $$ProfilesTableCreateCompanionBuilder,
          $$ProfilesTableUpdateCompanionBuilder,
          (Profile, $$ProfilesTableReferences),
          Profile,
          PrefetchHooks Function({
            bool questProgressRefs,
            bool objectiveProgressRefs,
          })
        > {
  $$ProfilesTableTableManager(_$AppDatabase db, $ProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> gameMode = const Value.absent(),
                Value<int> playerLevel = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion(
                id: id,
                gameMode: gameMode,
                playerLevel: playerLevel,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String gameMode,
                Value<int> playerLevel = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion.insert(
                id: id,
                gameMode: gameMode,
                playerLevel: playerLevel,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProfilesTable, Profile>(table),
                  $$ProfilesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({questProgressRefs = false, objectiveProgressRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (questProgressRefs) db.questProgress,
                    if (objectiveProgressRefs) db.objectiveProgress,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (questProgressRefs)
                        await $_getPrefetchedDataByColumns<
                          Profile,
                          $ProfilesTable,
                          QuestProgressEntry,
                          $QuestProgressTable
                        >(
                          currentTable: table,
                          referencedTable: $$ProfilesTableReferences
                              ._questProgressRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProfilesTableReferences(
                                db,
                                table,
                                p0,
                              ).questProgressRefs,
                          currentColumn: 'id',
                          referencedColumn: 'profileId',
                          typedResults: items,
                        ),
                      if (objectiveProgressRefs)
                        await $_getPrefetchedDataByColumns<
                          Profile,
                          $ProfilesTable,
                          ObjectiveProgressEntry,
                          $ObjectiveProgressTable
                        >(
                          currentTable: table,
                          referencedTable: $$ProfilesTableReferences
                              ._objectiveProgressRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProfilesTableReferences(
                                db,
                                table,
                                p0,
                              ).objectiveProgressRefs,
                          currentColumn: 'id',
                          referencedColumn: 'profileId',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProfilesTable,
      Profile,
      $$ProfilesTableFilterComposer,
      $$ProfilesTableOrderingComposer,
      $$ProfilesTableAnnotationComposer,
      $$ProfilesTableCreateCompanionBuilder,
      $$ProfilesTableUpdateCompanionBuilder,
      (Profile, $$ProfilesTableReferences),
      Profile,
      PrefetchHooks Function({
        bool questProgressRefs,
        bool objectiveProgressRefs,
      })
    >;
typedef $$QuestProgressTableCreateCompanionBuilder =
    QuestProgressCompanion Function({
      required String profileId,
      required String questId,
      required String state,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$QuestProgressTableUpdateCompanionBuilder =
    QuestProgressCompanion Function({
      Value<String> profileId,
      Value<String> questId,
      Value<String> state,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$QuestProgressTableReferences
    extends
        BaseReferences<_$AppDatabase, $QuestProgressTable, QuestProgressEntry> {
  $$QuestProgressTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProfilesTable _profileIdTable(_$AppDatabase db) =>
      db.profiles.createAlias('questProgress__profileId__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<String>('profileId')!;

    final manager = $$ProfilesTableTableManager(
      $_db,
      $_db.profiles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$QuestProgressTableFilterComposer
    extends Composer<_$AppDatabase, $QuestProgressTable> {
  $$QuestProgressTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get questId => $composableBuilder(
    column: $table.questId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableFilterComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QuestProgressTableOrderingComposer
    extends Composer<_$AppDatabase, $QuestProgressTable> {
  $$QuestProgressTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get questId => $composableBuilder(
    column: $table.questId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableOrderingComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QuestProgressTableAnnotationComposer
    extends Composer<_$AppDatabase, $QuestProgressTable> {
  $$QuestProgressTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get questId =>
      $composableBuilder(column: $table.questId, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableAnnotationComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QuestProgressTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $QuestProgressTable,
          QuestProgressEntry,
          $$QuestProgressTableFilterComposer,
          $$QuestProgressTableOrderingComposer,
          $$QuestProgressTableAnnotationComposer,
          $$QuestProgressTableCreateCompanionBuilder,
          $$QuestProgressTableUpdateCompanionBuilder,
          (QuestProgressEntry, $$QuestProgressTableReferences),
          QuestProgressEntry,
          PrefetchHooks Function({bool profileId})
        > {
  $$QuestProgressTableTableManager(_$AppDatabase db, $QuestProgressTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QuestProgressTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QuestProgressTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QuestProgressTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> profileId = const Value.absent(),
                Value<String> questId = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QuestProgressCompanion(
                profileId: profileId,
                questId: questId,
                state: state,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String profileId,
                required String questId,
                required String state,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => QuestProgressCompanion.insert(
                profileId: profileId,
                questId: questId,
                state: state,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$QuestProgressTable, QuestProgressEntry>(table),
                  $$QuestProgressTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({profileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (profileId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.profileId,
                        referencedTable: $$QuestProgressTableReferences
                            ._profileIdTable(db),
                        referencedColumn: $$QuestProgressTableReferences
                            ._profileIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$QuestProgressTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $QuestProgressTable,
      QuestProgressEntry,
      $$QuestProgressTableFilterComposer,
      $$QuestProgressTableOrderingComposer,
      $$QuestProgressTableAnnotationComposer,
      $$QuestProgressTableCreateCompanionBuilder,
      $$QuestProgressTableUpdateCompanionBuilder,
      (QuestProgressEntry, $$QuestProgressTableReferences),
      QuestProgressEntry,
      PrefetchHooks Function({bool profileId})
    >;
typedef $$ObjectiveProgressTableCreateCompanionBuilder =
    ObjectiveProgressCompanion Function({
      required String profileId,
      required String questId,
      required String objectiveId,
      Value<int> count,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ObjectiveProgressTableUpdateCompanionBuilder =
    ObjectiveProgressCompanion Function({
      Value<String> profileId,
      Value<String> questId,
      Value<String> objectiveId,
      Value<int> count,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ObjectiveProgressTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ObjectiveProgressTable,
          ObjectiveProgressEntry
        > {
  $$ObjectiveProgressTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProfilesTable _profileIdTable(_$AppDatabase db) =>
      db.profiles.createAlias('objectiveProgress__profileId__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<String>('profileId')!;

    final manager = $$ProfilesTableTableManager(
      $_db,
      $_db.profiles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ObjectiveProgressTableFilterComposer
    extends Composer<_$AppDatabase, $ObjectiveProgressTable> {
  $$ObjectiveProgressTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get questId => $composableBuilder(
    column: $table.questId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get objectiveId => $composableBuilder(
    column: $table.objectiveId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableFilterComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObjectiveProgressTableOrderingComposer
    extends Composer<_$AppDatabase, $ObjectiveProgressTable> {
  $$ObjectiveProgressTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get questId => $composableBuilder(
    column: $table.questId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get objectiveId => $composableBuilder(
    column: $table.objectiveId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableOrderingComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObjectiveProgressTableAnnotationComposer
    extends Composer<_$AppDatabase, $ObjectiveProgressTable> {
  $$ObjectiveProgressTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get questId =>
      $composableBuilder(column: $table.questId, builder: (column) => column);

  GeneratedColumn<String> get objectiveId => $composableBuilder(
    column: $table.objectiveId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get count =>
      $composableBuilder(column: $table.count, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableAnnotationComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObjectiveProgressTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ObjectiveProgressTable,
          ObjectiveProgressEntry,
          $$ObjectiveProgressTableFilterComposer,
          $$ObjectiveProgressTableOrderingComposer,
          $$ObjectiveProgressTableAnnotationComposer,
          $$ObjectiveProgressTableCreateCompanionBuilder,
          $$ObjectiveProgressTableUpdateCompanionBuilder,
          (ObjectiveProgressEntry, $$ObjectiveProgressTableReferences),
          ObjectiveProgressEntry,
          PrefetchHooks Function({bool profileId})
        > {
  $$ObjectiveProgressTableTableManager(
    _$AppDatabase db,
    $ObjectiveProgressTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ObjectiveProgressTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ObjectiveProgressTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ObjectiveProgressTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> profileId = const Value.absent(),
                Value<String> questId = const Value.absent(),
                Value<String> objectiveId = const Value.absent(),
                Value<int> count = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ObjectiveProgressCompanion(
                profileId: profileId,
                questId: questId,
                objectiveId: objectiveId,
                count: count,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String profileId,
                required String questId,
                required String objectiveId,
                Value<int> count = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ObjectiveProgressCompanion.insert(
                profileId: profileId,
                questId: questId,
                objectiveId: objectiveId,
                count: count,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ObjectiveProgressTable, ObjectiveProgressEntry>(
                    table,
                  ),
                  $$ObjectiveProgressTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({profileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (profileId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.profileId,
                        referencedTable: $$ObjectiveProgressTableReferences
                            ._profileIdTable(db),
                        referencedColumn: $$ObjectiveProgressTableReferences
                            ._profileIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ObjectiveProgressTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ObjectiveProgressTable,
      ObjectiveProgressEntry,
      $$ObjectiveProgressTableFilterComposer,
      $$ObjectiveProgressTableOrderingComposer,
      $$ObjectiveProgressTableAnnotationComposer,
      $$ObjectiveProgressTableCreateCompanionBuilder,
      $$ObjectiveProgressTableUpdateCompanionBuilder,
      (ObjectiveProgressEntry, $$ObjectiveProgressTableReferences),
      ObjectiveProgressEntry,
      PrefetchHooks Function({bool profileId})
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => AppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppSettingsTable, AppSetting>(table),
                  BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$DatasetStatesTableTableManager get datasetStates =>
      $$DatasetStatesTableTableManager(_db, _db.datasetStates);
  $$RemoteManifestsTableTableManager get remoteManifests =>
      $$RemoteManifestsTableTableManager(_db, _db.remoteManifests);
  $$ItemsTableTableManager get items =>
      $$ItemsTableTableManager(_db, _db.items);
  $$ItemTypesTableTableManager get itemTypes =>
      $$ItemTypesTableTableManager(_db, _db.itemTypes);
  $$ItemCategoriesTableTableManager get itemCategories =>
      $$ItemCategoriesTableTableManager(_db, _db.itemCategories);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$TaskObjectivesTableTableManager get taskObjectives =>
      $$TaskObjectivesTableTableManager(_db, _db.taskObjectives);
  $$TradersTableTableManager get traders =>
      $$TradersTableTableManager(_db, _db.traders);
  $$HideoutStationsTableTableManager get hideoutStations =>
      $$HideoutStationsTableTableManager(_db, _db.hideoutStations);
  $$CraftsTableTableManager get crafts =>
      $$CraftsTableTableManager(_db, _db.crafts);
  $$BartersTableTableManager get barters =>
      $$BartersTableTableManager(_db, _db.barters);
  $$MapsTableTableManager get maps => $$MapsTableTableManager(_db, _db.maps);
  $$GameRecordsTableTableManager get gameRecords =>
      $$GameRecordsTableTableManager(_db, _db.gameRecords);
  $$PriceHistoryTableTableManager get priceHistory =>
      $$PriceHistoryTableTableManager(_db, _db.priceHistory);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db, _db.profiles);
  $$QuestProgressTableTableManager get questProgress =>
      $$QuestProgressTableTableManager(_db, _db.questProgress);
  $$ObjectiveProgressTableTableManager get objectiveProgress =>
      $$ObjectiveProgressTableTableManager(_db, _db.objectiveProgress);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
}
