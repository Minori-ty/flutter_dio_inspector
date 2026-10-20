## 0.2.0

- List rows now show the path **relative to `baseUrl`**, not the full path after the host. A base URL
  of `https://api.example.com/v1` turns `/v1/todo`, `/v1/user` into `/todo`, `/user`, so the version
  prefix is no longer repeated on every row. `NetworkEntry` gains a `baseUrl` field; the detail view,
  URL copy and cURL export still carry the full URL.
- Console logging: set `NetworkPanelConfig(logToConsole: true)` and each finished request prints a
  coloured line via `debugPrint` — method (coloured per verb), the path relative to `baseUrl`, duration,
  status code, and the captured request/response bodies. The formatter is exported as
  `formatConsoleLog`; pass `color: false` for the plain-text form.

## 0.1.0

Initial release — an in-app network panel for [Dio](https://pub.dev/packages/dio).

- `DioNetworkPanel` — a drop-in wrapper that renders a draggable floating ball over the app.
- `DioNetworkPanelInterceptor` — a `dio` `Interceptor` that records every request, response and
  error, including timeouts, cancellations and connection failures. Add it **first** so it sees
  requests that earlier interceptors would otherwise reject.
- `NetworkStore` — a bounded store (a count cap plus a byte budget over stored body previews),
  exposed as a `ChangeNotifier`.
- Full-screen inspector: grouped card list, method/status colour coding, method and text filters,
  a detail view with headers, bodies and cURL export, and tap-to-copy with a confirmation toast.
- JSON bodies render as a syntax-highlighted, collapsible tree; anything that does not parse falls
  back to a plain text view.
- Unread tracking: the ball badge counts requests captured since the panel was last dismissed, and
  opening an entry clears that row's `NEW` marker.
- Chinese and English, starting in English, with a language switch in the list header.

### Behaviour notes

- **Nothing is redacted by default.** `Authorization`, `Cookie` and the rest are shown exactly as
  sent. The header that explains a failure is usually the one carrying the credentials, and masking
  it to `••••••` makes the panel useless for the job it exists to do. Redaction is opt-in:
  `NetworkPanelConfig(redactedHeaders: sensitiveHeaders)`; `sensitiveHeaders` and
  `defaultRedactedHeaders` (now empty) are exported.
- **`PanelLanguageController.onChanged`** is the slot for the host app's persistence. Pass a
  callback that writes `language.name` and the choice survives a restart; omit it and nothing is
  saved. The package ships no storage dependency. `PanelLanguage.fromCode` reads a stored code back
  tolerantly, falling back to English for a missing or unknown value.
- Zero native code, no codegen, no state-management lock-in — one `dio` dependency and `flutter`.
