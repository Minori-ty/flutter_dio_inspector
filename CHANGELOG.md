## Unreleased

- **Nothing is redacted by default.** `Authorization`, `Cookie` and the rest are shown exactly as
  sent. The header that explains a failure is usually the one carrying the credentials, and masking
  it to `••••••` makes the panel useless for the job it exists to do. Redaction is unchanged and now
  opt-in: `NetworkPanelConfig(redactedHeaders: sensitiveHeaders)` restores the old list, and
  `sensitiveHeaders` is exported alongside `defaultRedactedHeaders` (now empty).
- **Chinese and English.** Every string in the panel now comes from `PanelStrings`, and the list
  header carries a switch (`EN` / `中文`). The panel **starts in English**; pass a
  `PanelLanguageController(initial: PanelLanguage.zh)` to `DioNetworkPanel` to start in Chinese, or
  to keep the choice across restarts.
- **`PanelLanguageController.onChanged`** — a slot for the host app's own persistence. Pass a
  callback that writes `language.name` and the choice survives a restart; omit it and nothing is
  saved. The package still ships no storage dependency. `PanelLanguage.fromCode` reads the code back
  tolerantly, falling back to English for a missing or unknown value.
- The status code in the list is no longer bold. Its colour already says whether the request
  succeeded, and the weight competed with the request path on every row.

## 0.1.0

Initial release.

- `DioNetworkPanel` — drop-in wrapper that renders a draggable floating ball over your app.
- `DioNetworkPanelInterceptor` — a `dio` `Interceptor` that records every request, response and
  error, including timeouts, cancellations and connection failures.
- `NetworkStore` — a bounded store (ring buffer plus a byte budget) exposed as a `ChangeNotifier`.
- Full-screen inspector: grouped card list, method/status colour coding, method and text filters,
  detail view with headers, bodies and cURL export, tap-to-copy with a confirmation toast.
- Unread tracking: the ball badge counts requests captured since the panel was last dismissed, and
  opening an entry clears that row's `NEW` marker.
- Zero native code, no state-management lock-in — one `dio` dependency and `flutter`.
