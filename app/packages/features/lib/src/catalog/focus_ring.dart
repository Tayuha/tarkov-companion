import 'package:material_ui/material_ui.dart';

import '../theme/app_tokens.dart';

/// Asks the active list to move keyboard focus to its search field.
///
/// Bound to `/` by the catalog and quest screens.
class FocusSearchIntent extends Intent {
  const FocusSearchIntent();
}

/// Asks the active list to clear its search and return focus to the screen.
///
/// Bound to Escape by the catalog and quest screens while the search field has
/// focus or text.
class DismissListFocusIntent extends Intent {
  const DismissListFocusIntent();
}

/// An [Action] whose enablement is evaluated when the key is pressed.
///
/// [CallbackAction] is always enabled, which would swallow `/` while the search
/// field is focused. This variant lets a screen say "only handle this key when
/// the field is not already focused".
class GuardedCallbackAction<T extends Intent> extends Action<T> {
  GuardedCallbackAction({required this.enabled, required this.onInvoke});

  final bool Function() enabled;
  final VoidCallback onInvoke;

  @override
  bool isEnabled(T intent) => enabled();

  @override
  Object? invoke(T intent) {
    onInvoke();
    return null;
  }
}

/// Paints the tokenised focus ring around any focused descendant.
///
/// The wrapper is not itself a tab stop: it observes the focused InkWell,
/// DropdownButton, IconButton or TextField underneath it. The ring is a
/// [Positioned.fill] overlay so it never changes the child's size or position.
///
/// Set [scrollIntoView] on list rows: gaining focus scrolls the row into the
/// nearest scrollable, which keeps Tab traversal usable in a virtualised list.
class AppFocusRing extends StatefulWidget {
  const AppFocusRing({
    super.key,
    required this.child,
    this.borderRadius,
    this.focusKey,
    this.ringKey,
    this.scrollIntoView = false,
  });

  final Widget child;

  /// Corner radius of the ring. The control's own radius is the sensible
  /// default: a 2 px radius for inputs and rows, a pill for chips.
  final BorderRadius? borderRadius;

  /// Optional key for the internal [Focus] widget, so tests can assert which
  /// control holds focus without pointer input.
  final Key? focusKey;

  /// Optional key for the painted ring, present only while the control is
  /// focused.
  final Key? ringKey;

  /// Scroll the focused descendant into view when it gains focus.
  final bool scrollIntoView;

  @override
  State<AppFocusRing> createState() => _AppFocusRingState();
}

class _AppFocusRingState extends State<AppFocusRing> {
  final FocusNode _node = FocusNode(
    debugLabel: 'AppFocusRing',
    skipTraversal: true,
  );
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _node.removeListener(_handleFocusChange);
    _node.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final hasFocus = _node.hasFocus;
    if (hasFocus == _hasFocus) {
      return;
    }
    setState(() => _hasFocus = hasFocus);
    if (hasFocus && widget.scrollIntoView) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (Scrollable.maybeOf(context) == null) {
          return;
        }
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final radius =
        widget.borderRadius ?? BorderRadius.circular(tokens.radiusSm);

    return Focus(
      key: widget.focusKey,
      focusNode: _node,
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_hasFocus)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: widget.ringKey,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: tokens.focusRing,
                      width: tokens.focusRingWidth,
                    ),
                    borderRadius: radius,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
