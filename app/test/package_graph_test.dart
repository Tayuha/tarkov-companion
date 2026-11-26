import 'package:flutter_test/flutter_test.dart';
import 'package:tarkov_companion_core/tarkov_companion_core.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

void main() {
  test('the app can use a symbol from every workspace package', () {
    const Result<int> result = Ok(1);
    final dataset = DatasetKind.parse('items');
    const header = SectionHeader(title: 'Items');

    expect(result.valueOrNull, 1);
    expect(dataset.valueOrNull, DatasetKind.items);
    expect(header.title, 'Items');
  });
}
