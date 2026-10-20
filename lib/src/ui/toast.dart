import 'dart:async';

import 'package:flutter/material.dart';

import 'panel_theme.dart';

/// Owns a transient toast message and its dismissal timer.
///
/// Shared by the list and the detail page so both behave identically — and so the
/// timer is always cancelled on dispose rather than firing into a dead `State`.
mixin ToastStateMixin<T extends StatefulWidget> on State<T> {
  String? toastMessage;

  Timer? _toastTimer;

  void showToast(
    String message, {
    Duration duration = const Duration(milliseconds: 1600),
  }) {
    _toastTimer?.cancel();
    setState(() => toastMessage = message);
    _toastTimer = Timer(duration, () {
      if (mounted) setState(() => toastMessage = null);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }
}

/// Bottom-centred confirmation pill.
///
/// Returns a [Positioned.fill], so it has to be placed directly inside the [Stack]
/// that fills the page. It is `IgnorePointer`-wrapped so it never swallows a tap.
///
/// The caller owns the message state: pass `null` to hide it. Keeping the state
/// with the caller is what lets a new message restart the fade without the widget
/// having to guess whether it is the same message as before.
class ToastOverlay extends StatelessWidget {
  const ToastOverlay({super.key, required this.message, required this.theme});

  final String? message;
  final NetworkPanelTheme theme;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.4),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: message == null
                    ? const SizedBox.shrink()
                    : _Pill(
                        key: ValueKey<String>(message!),
                        message: message!,
                        theme: theme,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.message, required this.theme});

  final String message;
  final NetworkPanelTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        // Inverted against the page in both modes, so the pill reads as a
        // transient overlay rather than as one more card.
        color: theme.text,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: theme.card,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
