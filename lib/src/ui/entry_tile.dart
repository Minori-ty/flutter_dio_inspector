import 'package:flutter/material.dart';

import '../core/entry.dart';
import '../core/format.dart';
import '../i18n/panel_strings.dart';
import 'middle_ellipsis.dart';
import 'panel_theme.dart';
import 'primitives.dart';

/// One row in the request list.
///
/// A rounded card on the grouped background. The `NEW` marker is a sibling of the
/// card inside a [Stack] rather than a child of it: positioned children do not
/// contribute to the stack's size, so a marked row is exactly as tall as an
/// unmarked one and the list stays even.
class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.entry,
    required this.theme,
    required this.isNew,
    required this.onTap,
    this.strings = PanelStrings.zh,
  });

  final NetworkEntry entry;
  final NetworkPanelTheme theme;
  final bool isNew;
  final VoidCallback onTap;
  final PanelStrings strings;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: theme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.border, width: 0.5),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        MethodBadge(method: entry.method, theme: theme),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              MiddleEllipsisText(
                                text: entry.displayPath,
                                style: TextStyle(
                                  color: theme.text,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                formatDuration(entry.duration),
                                style: TextStyle(
                                  color: theme.textMuted,
                                  fontSize: 13,
                                  fontFeatures: const <FontFeature>[
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          strings.statusLabel(entry),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: theme.stateColor(entry),
                            fontSize: 17,
                            // Regular weight: the colour already carries the
                            // outcome, and a bold code competed with the path for
                            // attention on every row.
                            fontWeight: FontWeight.w400,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (entry.errorMessage != null) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        entry.errorMessage!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.danger, fontSize: 12, height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (isNew)
          Positioned(
            top: -7,
            left: -5,
            child: PanelChip(label: 'NEW', color: theme.danger),
          ),
      ],
    );
  }
}
