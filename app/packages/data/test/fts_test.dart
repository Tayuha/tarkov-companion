import 'package:drift/drift.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import 'support/database_helpers.dart';

void main() {
  test('insert, update and delete keep items_fts in sync', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);

    Future<int> match(String query) async {
      final rows = await db
          .customSelect(
            '''
            SELECT items.id
            FROM items
            JOIN items_fts ON items_fts.rowid = items.rowid
            WHERE items_fts MATCH ?
            ''',
            variables: [Variable<String>(query)],
          )
          .get();
      return rows.length;
    }

    await insertItem(
      db,
      id: 'item-m4a1',
      name: 'Colt M4A1 assault rifle',
      shortName: 'M4A1',
      normalizedName: 'colt-m4a1-assault-rifle',
    );
    expect(await match('m4a1'), 1);
    expect(await match('colt'), 1);
    expect(await match('rifle'), 1);

    // Update: the old term leaves the index, the new one enters it.
    await (db.update(
      db.items,
    )..where((row) => row.id.equals('item-m4a1'))).write(
      const ItemsCompanion(
        name: Value('Kiba Arms 5.56x45'),
        shortName: Value('Kiba'),
        normalizedName: Value('kiba-arms-556x45'),
      ),
    );
    expect(await match('m4a1'), 0);
    expect(await match('kiba'), 1);
    expect(await match('arms'), 1);

    // Delete: the index entry is removed with the row.
    await (db.delete(
      db.items,
    )..where((row) => row.id.equals('item-m4a1'))).go();
    expect(await match('kiba'), 0);

    final ftsRows = await db.customSelect('SELECT rowid FROM items_fts').get();
    expect(ftsRows, isEmpty);
  });

  test('the unicode61 tokenizer folds diacritics', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);

    await insertItem(
      db,
      id: 'item-accent',
      name: 'Café Crème optic',
      shortName: 'Crème',
      normalizedName: 'cafe-creme-optic',
    );

    Future<int> match(String query) async {
      final rows = await db
          .customSelect(
            '''
            SELECT items.id
            FROM items
            JOIN items_fts ON items_fts.rowid = items.rowid
            WHERE items_fts MATCH ?
            ''',
            variables: [Variable<String>(query)],
          )
          .get();
      return rows.length;
    }

    // `remove_diacritics 2` makes an unaccented query match accented text.
    expect(await match('cafe'), 1);
    expect(await match('creme'), 1);
    expect(await match('café'), 1);

    // A prefix query keeps working, for search-as-you-type.
    expect(await match('op*'), 1);
    expect(await match('nomatch'), 0);
  });

  test('inserting many items leaves one index row per item', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);

    for (var index = 0; index < 25; index++) {
      await insertItem(
        db,
        id: 'item-$index',
        name: 'Item number $index',
        normalizedName: 'item-number-$index',
      );
    }

    final ftsCount = await db
        .customSelect('SELECT count(*) AS n FROM items_fts')
        .getSingle();
    final itemCount = await db
        .customSelect('SELECT count(*) AS n FROM items')
        .getSingle();

    expect(ftsCount.read<int>('n'), 25);
    expect(itemCount.read<int>('n'), 25);
  });
}
