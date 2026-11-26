/// FTS5 schema for item search.
///
/// `items_fts` is an **external-content** FTS5 table over `items`: it stores
/// only the index, and reads the original text from `items` through `rowid`.
/// Three triggers keep the index in sync on `INSERT`, `UPDATE` and `DELETE`,
/// which covers whole-dataset replacement during ingestion (`DELETE` +
/// bulk insert) as well as edits.
///
/// The tokenizer is `unicode61 remove_diacritics 2`, so `cafe` matches `Café`
/// and `M4A1` matches `m4a1`. Only `name`, `shortName` and `normalizedName` are
/// indexed; `normalizedName` is already lower-case and diacritic-free upstream.
///
/// These statements are created by `AppDatabase` in `onCreate` and are not part
/// of drift's generated schema. `docs/schema.md` documents how the schema
/// snapshot covers them.
library;

/// The FTS5 virtual table. `content` and `content_rowid` tie it to `items`.
const createItemsFtsTable = '''
CREATE VIRTUAL TABLE items_fts USING fts5(
  name,
  shortName,
  normalizedName,
  content = 'items',
  content_rowid = 'rowid',
  tokenize = 'unicode61 remove_diacritics 2'
)''';

/// Keeps the index current when an item row is inserted.
const createItemsFtsInsertTrigger = '''
CREATE TRIGGER items_fts_ai AFTER INSERT ON items BEGIN
  INSERT INTO items_fts (rowid, name, shortName, normalizedName)
  VALUES (new.rowid, new.name, new.shortName, new.normalizedName);
END''';

/// Removes an item from the index when its row is deleted.
///
/// FTS5 external-content tables need the special `'delete'` row form so the
/// index, not the (already deleted) content table, drives the removal.
const createItemsFtsDeleteTrigger = '''
CREATE TRIGGER items_fts_ad AFTER DELETE ON items BEGIN
  INSERT INTO items_fts (items_fts, rowid, name, shortName, normalizedName)
  VALUES ('delete', old.rowid, old.name, old.shortName, old.normalizedName);
END''';

/// Re-indexes an item row when any indexed column changes.
const createItemsFtsUpdateTrigger = '''
CREATE TRIGGER items_fts_au AFTER UPDATE ON items BEGIN
  INSERT INTO items_fts (items_fts, rowid, name, shortName, normalizedName)
  VALUES ('delete', old.rowid, old.name, old.shortName, old.normalizedName);
  INSERT INTO items_fts (rowid, name, shortName, normalizedName)
  VALUES (new.rowid, new.name, new.shortName, new.normalizedName);
END''';

/// Every statement needed to build the item search schema, in order.
///
/// Run after the drift tables exist (`onCreate`) and on every database upgrade
/// that changes the `items` text columns.
const itemSearchSchema = <String>[
  createItemsFtsTable,
  createItemsFtsInsertTrigger,
  createItemsFtsDeleteTrigger,
  createItemsFtsUpdateTrigger,
];
