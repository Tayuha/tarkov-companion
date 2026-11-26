import 'package:material_ui/material_ui.dart';

/// A heading that introduces a section inside a feature screen.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (subtitle != null)
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
