import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/panel_strings.dart';
import 'panel_theme.dart';

/// Writes [text] to the clipboard and reports the outcome through [onResult].
///
/// The result is reported rather than assumed: `setData` can fail, and a copy
/// that silently does nothing is worse than one that says it failed.
Future<void> copyWithFeedback(
  String text,
  String label,
  PanelStrings strings,
  void Function(String message) onResult,
) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    onResult(strings.copied(label));
  } catch (_) {
    onResult(strings.copyFailed(label));
  }
}

/// Solid pill carrying the HTTP method.
class MethodBadge extends StatelessWidget {
  const MethodBadge({
    super.key,
    required this.method,
    required this.theme,
    this.fontSize = 11,
  });

  final String method;
  final NetworkPanelTheme theme;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.methodColor(method),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        method.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// A small rounded label, e.g. the `NEW` marker or a body kind.
class PanelChip extends StatelessWidget {
  const PanelChip({
    super.key,
    required this.label,
    required this.color,
    this.textColor,
    this.fontSize = 10,
  });

  final String label;
  final Color color;
  final Color? textColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor ?? Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Title above a card, with an optional trailing action.
///
/// When [onTap] is set the header becomes a toggle: a chevron appears before the
/// title, and tapping anywhere in the header flips [expanded]. The chevron matches
/// the one the JSON tree uses, so "this folds" looks the same everywhere in the
/// panel.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    required this.theme,
    this.trailing,
    this.onTap,
    this.expanded = true,
  });

  final String title;
  final NetworkPanelTheme theme;
  final Widget? trailing;

  /// Makes the header a toggle. Null leaves it a plain label.
  final VoidCallback? onTap;

  /// Whether the section below is open. Only drives the chevron.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: <Widget>[
        if (onTap != null) ...<Widget>[
          AnimatedRotation(
            turns: expanded ? 0.25 : 0,
            duration: const Duration(milliseconds: 120),
            child: Icon(Icons.chevron_right, size: 16, color: theme.textFaint),
          ),
          const SizedBox(width: 2),
        ],
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              color: theme.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );

    if (onTap == null) {
      return Padding(padding: const EdgeInsets.only(bottom: 6), child: row);
    }

    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          // Extra vertical padding on the tappable variant: the label itself is
          // only 11px tall, which would make a very thin target.
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: row,
        ),
      ),
    );
  }
}

/// The white rounded card a section's rows sit in.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, required this.theme});

  final Widget child;
  final NetworkPanelTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.border, width: 0.5),
      ),
      child: child,
    );
  }
}

/// `label` in a fixed column, value beside it.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    required this.value,
    required this.theme,
    this.mono = false,
  });

  final String label;
  final String value;
  final NetworkPanelTheme theme;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Sized for the longest label actually used, not the longest one
          // imaginable: a wider column is width taken from the value, and long
          // values are the ones that need it.
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: TextStyle(color: theme.textMuted, fontSize: 12, height: 1.4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: (mono ? monospaceStyle : const TextStyle()).copyWith(
                color: theme.text,
                fontSize: mono ? 12 : 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stacks rows inside a [SectionCard], drawing a hairline between them.
///
/// Separators rather than per-row bottom borders: a row cannot know whether it is
/// last, and a stray hairline sitting on the card's rounded corner is exactly the
/// kind of detail that makes a panel look unfinished.
class Rows extends StatelessWidget {
  const Rows({super.key, required this.children, required this.theme});

  final List<Widget> children;
  final NetworkPanelTheme theme;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      rows.add(children[index]);
      if (index != children.length - 1) {
        rows.add(Divider(height: 0.5, thickness: 0.5, color: theme.border));
      }
    }
    // `stretch`, not the default `center`. A Column hands its children *loose*
    // cross-axis constraints unless it stretches, so a `Text` shrinks to its own
    // intrinsic width — and a short row like `accept: application/json` then sits
    // centred in the card instead of against its left edge.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// `name: value` on one line, with the name bold.
///
/// Built as a single rich paragraph rather than two columns so a long value wraps
/// onto the following line instead of being squeezed into a narrow second column.
class HeaderRow extends StatelessWidget {
  const HeaderRow({
    super.key,
    required this.name,
    required this.value,
    required this.theme,
  });

  final String name;
  final String value;
  final NetworkPanelTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '$name: ',
              style: TextStyle(
                color: theme.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
              style: monospaceStyle.copyWith(color: theme.text, fontSize: 12),
            ),
          ],
        ),
        style: const TextStyle(height: 1.45),
      ),
    );
  }
}

/// A monospace block, for bodies and cURL commands.
class MonoBlock extends StatelessWidget {
  const MonoBlock({
    super.key,
    required this.text,
    required this.theme,
    required this.placeholder,
  });

  final String text;
  final NetworkPanelTheme theme;

  /// Shown instead of the text when [text] is empty. Required rather than
  /// defaulted: a Chinese default would quietly leak into an English panel.
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final isEmpty = text.isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        isEmpty ? placeholder : text,
        style: monospaceStyle.copyWith(
          color: isEmpty ? theme.textFaint : theme.text,
          fontSize: 12,
          height: 1.5,
        ),
      ),
    );
  }
}

/// Icon-only button with a mandatory label.
///
/// [label] is required because an icon alone says nothing to a screen reader, and
/// a tooltip alone is not announced reliably.
class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.theme,
    this.color,
    this.size = 20,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final NetworkPanelTheme theme;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: size, color: color ?? theme.textFaint),
      tooltip: label,
      // A 20px glyph is well under the minimum touch target on its own.
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      splashRadius: 20,
    );
  }
}

/// Centred placeholder shown when the list has nothing in it.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, required this.theme});

  final String message;
  final NetworkPanelTheme theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.textFaint, fontSize: 13, height: 1.6),
        ),
      ),
    );
  }
}
