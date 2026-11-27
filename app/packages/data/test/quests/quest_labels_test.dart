import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/database_helpers.dart';

void main() {
  test('trader and map labels are ordered by display name', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);

    for (final (id, name) in [('t2', 'Therapist'), ('t1', 'Prapor')]) {
      await db.customStatement(
        'INSERT INTO traders (id, name, normalizedName, payload) VALUES (?, ?, ?, ?)',
        [id, name, name.toLowerCase(), '{}'],
      );
    }
    for (final (id, name) in [('m2', 'Woods'), ('m1', 'Customs')]) {
      await db.customStatement(
        'INSERT INTO maps (id, name, normalizedName, payload) VALUES (?, ?, ?, ?)',
        [id, name, name.toLowerCase(), '{}'],
      );
    }

    final repository = QuestRepository(db);
    final traders = await repository.traderLabels();
    final maps = await repository.mapLabels();

    expect(traders.map((label) => label.name), ['Prapor', 'Therapist']);
    expect(traders.map((label) => label.id), ['t1', 't2']);
    expect(maps.map((label) => label.name), ['Customs', 'Woods']);
  });
}
