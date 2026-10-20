import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n/panel_strings.dart';
import 'panel_theme.dart';

/// Width of the white ring that separates the ball from whatever is behind it.
///
/// Painted inside the ball's bounds — a `CircleBorder` side strokes at
/// `radius - width / 2` — so it does not change the ball's overall size.
const double _ballRing = 3;

/// Diameter of the unread badge, ring included.
const double _badgeSize = 24;

/// The draggable floating ball that opens the panel.
///
/// The badge counts requests captured since the panel was last dismissed — an
/// unread count, not an error count. Errors are surfaced inside the panel
/// instead, so the badge answers one question: is there anything new to look at?
class FloatBall extends StatelessWidget {
  const FloatBall({
    super.key,
    required this.theme,
    required this.badge,
    required this.onTap,
    this.size = 54,
    this.strings = PanelStrings.zh,
  });

  final NetworkPanelTheme theme;
  final int badge;
  final VoidCallback onTap;
  final double size;

  /// Wording for the screen-reader label.
  final PanelStrings strings;

  @override
  Widget build(BuildContext context) {
    final label = strings.ballLabel(badge);

    // The badge straddles the ball's edge: its centre sits on the circle at 45°,
    // so half of it overlaps the ball and half hangs outside. Positioning it by
    // the corner of the box instead puts it further out — at that distance the
    // two circles stop intersecting and the badge reads as a separate object
    // floating next to the ball.
    final radius = size / 2;
    final diagonal = radius / math.sqrt2;

    return Semantics(
      button: true,
      label: label,
      // The badge is a *sibling* of the ball's own `Material`, so it does not
      // inherit that one's `DefaultTextStyle`. Without a `Material` of its own it
      // falls back to `MaterialApp`'s error style — monospace, and a **double
      // yellow underline**. Setting `color` does not clear it: `decoration`,
      // `decorationColor` and `decorationStyle` are inherited separately from the
      // colour, which is why the digit showed two yellow lines under it.
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Material(
              color: theme.accent,
              // The ring is part of the shape rather than a wrapping Container so
              // it also clips the ink splash.
              shape: const CircleBorder(
                side: BorderSide(color: Colors.white, width: _ballRing),
              ),
              elevation: 6,
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Icon(
                    Icons.network_check,
                    color: theme.onAccent,
                    size: size * 0.48,
                  ),
                ),
              ),
            ),
            if (badge > 0)
              Positioned(
                // Anchored by its right edge so `99+` grows inward, over the ball,
                // rather than off the side of the screen.
                right: size - radius - diagonal - _badgeSize / 2,
                top: radius - diagonal - _badgeSize / 2,
                child: _UnreadBadge(
                  label: badge > 99 ? '99+' : '$badge',
                  color: theme.danger,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A round badge straddling the ball's top-right corner.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      // `minWidth`/`minHeight` rather than a fixed square: one or two digits make
      // a circle, and `99+` grows into a pill instead of squashing.
      constraints: const BoxConstraints(minWidth: _badgeSize, minHeight: _badgeSize),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(_badgeSize / 2),
        // The white ring is what makes the badge read as sitting *on* the ball.
        // Without it the red and the blue merge into one silhouette.
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}
