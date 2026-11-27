/// A selectable trader or map for the quest filters.
///
/// The quest dataset stores upstream identifiers; this is the resolved display
/// pair the UI needs for dropdowns and row labels.
final class QuestLabel {
  const QuestLabel({required this.id, required this.name});

  final String id;
  final String name;
}
