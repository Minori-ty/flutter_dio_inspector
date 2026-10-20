# flutter_dio_inspector

An in-app network panel for [Dio](https://pub.dev/packages/dio): a draggable floating ball with an
unread badge, and a full-screen inspector for requests, responses, headers, bodies and cURL.

No native code, no codegen, no state-management lock-in. One runtime dependency: `dio`.

<table>
  <tr>
    <td><img src="https://raw.githubusercontent.com/Minori-ty/flutter_dio_inspector/refs/heads/master/images/1.jpg" width="400" alt="screenshot 1"></td>
    <td><img src="https://raw.githubusercontent.com/Minori-ty/flutter_dio_inspector/refs/heads/master/images/2.jpg" width="400" alt="screenshot 2"></td>
  </tr>
</table>

## Install

```sh
flutter pub add flutter_dio_inspector
```

## Quick start

Two pieces: the interceptor that records traffic, and the widget that shows it.

```dart
import 'package:dio/dio.dart';
import 'package:flutter_dio_inspector/flutter_dio_inspector.dart';
import 'package:flutter/material.dart';

final store = NetworkStore();
final navigatorKey = GlobalKey<NavigatorState>();

final dio = Dio()
  ..interceptors.add(DioNetworkPanelInterceptor(store: store));

void main() => runApp(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) => DioNetworkPanel(
          store: store,
          navigatorKey: navigatorKey,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const HomePage(),
      ),
    );
```

Then use `dio` as usual. Every request appears in the panel; nothing else to wire.

### Why `navigatorKey`

`MaterialApp.builder` wraps the `Navigator`, so a context taken there has no `Navigator` ancestor to
push onto — the key is how the panel reaches the one the app created. If you would rather not pass
one, put `DioNetworkPanel` somewhere below a `Navigator` instead (a `Stack` on a page, say) and the
nearest one is used.

### Gate it to debug builds

The panel is a development tool. Keeping it out of release builds is one line:

```dart
if (kDebugMode) dio.interceptors.add(DioNetworkPanelInterceptor(store: store));
```

and `hideBall: !kDebugMode` on the widget, or simply omit the widget in release.

## What it captures

| Captured | Notes |
| --- | --- |
| Method, full URL, query | resolved through `baseUrl` and `queryParameters` |
| Request headers | as sent, including `Authorization` — redaction is opt-in |
| Request body | JSON, form, multipart, text, bytes |
| Status code and message | including the response attached to a `badResponse` |
| Response headers | |
| Response body | truncated to a byte budget, full size always reported |
| Duration | from the interceptor seeing the request to the terminal callback |
| Failure reason | `timeout` / `canceled` / `badResponse` / `certificate` / `connection`, plus dio's exact `DioExceptionType` name |

## Configuration

```dart
NetworkStore(
  config: NetworkPanelConfig(
    enabled: true,
    logToConsole: false,               // print a coloured line per finished request
    maxEntries: 200,                   // retained rows
    maxBytes: 4 * 1024 * 1024,         // bytes of body preview held in memory
    bodyLimit: 32 * 1024,              // per-body capture limit
    redactedHeaders: sensitiveHeaders, // opt-in; nothing is hidden by default
    ignore: (uri, method) => uri.path.startsWith('/health'),
  ),
);
```

`config` is a setter too, so `store.config = ...` re-applies the limits immediately.

**Console logging.** With `logToConsole: true`, the interceptor prints one coloured line per finished
request via `debugPrint` — method (coloured per verb), the path relative to `baseUrl`, duration, status
code, and the captured request/response bodies:

```text
GET /todo 140ms 200
  req  {"title":"ship it"}
  res  {"ok":true}
```

**Two independent limits protect the app.** `maxEntries` caps the row count; `maxBytes` caps the
stored body previews. A 40 MB download costs only the `bodyLimit` preview, and if a single body still
exceeds the whole byte budget the newest entry keeps its metadata — size, kind, MIME type — while its
preview is dropped. The newest entry is never evicted: an inspector that loses the request you just
made is useless.

**Nothing is redacted by default.** The header that most often explains a failure is the one carrying
the credentials — a missing `Bearer` prefix, a token from the wrong environment, one that expired an
hour ago. Masking it to `••••••` is the panel refusing to answer the question you opened it for.

Opt in when the panel runs somewhere screenshots get shared:

```dart
NetworkStore(config: NetworkPanelConfig(redactedHeaders: sensitiveHeaders));
```

`sensitiveHeaders` is the ready-made list (`authorization`, `proxy-authorization`, `cookie`,
`set-cookie`, `x-api-key`, `x-auth-token`); pass your own set to hide something else, or
`defaultRedactedHeaders` (empty) to turn it back off. Redaction is applied in the store, not at the
call site, so setting the config is enough — no code path can store a value it should have hidden by
forgetting to.

## The panel

- **List** — rounded cards on a grouped background, one per request, newest first. Method is a solid
  colour-coded pill; the path truncates in the *middle* so both the leading segments and the query
  stay visible.
- **Filters** — method chips plus a case-insensitive search over URL and method.
- **Detail** — overview, error, headers as `name: value` with the name bold, request and response
  bodies, and cURL. **The two header sections start folded**: on a phone they push the bodies below
  the fold, and the bodies are what you opened the request for. Each folded header still shows how
  many headers are inside it, and the copy button stays reachable without unfolding.
- **JSON bodies** — syntax-highlighted and foldable. Objects and arrays collapse to `{ … } 3 fields`,
  and the section header carries expand-all / collapse-all. The tree opens two levels deep by
  default, so a large response shows its shape without the bulk. Anything that does not parse — a
  body truncated at the capture limit, HTML, plain text — falls back to the plain monospace view.
- **Copy** — tapping the URL row, or any copy glyph, writes to the clipboard and raises a
  confirmation. Copying is never silent.
- **Back** — detail → list → app, unwinding one level at a time, using the platform's own back
  gesture.

The panel carries its own palette and follows the system light/dark setting. There is no theme
parameter on purpose: a debug overlay that changes colour with the host app's branding is harder to
read across projects, and the method/status colours have to mean the same thing everywhere.

### Language

The panel ships in Chinese and English, and **starts in English**. The list header carries a switch —
the button is labelled with the language a tap will move *to* (`中文` while the panel is in English),
so it says what will happen rather than what is already on screen.

The choice lives in a `PanelLanguageController` that the ball and every page share. Omit it and the
panel makes its own; pass one to start in Chinese or to own the choice yourself:

```dart
final language = PanelLanguageController(initial: PanelLanguage.zh);

DioNetworkPanel(
  store: store,
  navigatorKey: navigatorKey,
  languageController: language,
  child: child ?? const SizedBox.shrink(),
);
```

The panel does not read the platform locale, not even for its default: its language is a property of
the team reading it, not of the device it runs on. It is also deliberately not wired to
`MaterialApp.locale` — a debug overlay has to work in an app that never added
`flutter_localizations`. Strings are a plain value (`PanelStrings`), not generated ARB output, so
there is no codegen step and no `intl` dependency.

#### Saving the choice

The package ships no storage dependency, so it saves nothing on its own. If your app already keeps
settings, hand the controller an `onChanged` callback and the language survives a restart; if it does
not, omit the callback and nothing is saved:

```dart
final prefs = await SharedPreferences.getInstance();

final panelLanguage = PanelLanguageController(
  initial: PanelLanguage.fromCode(prefs.getString('flutter_dio_inspector.language')),
  onChanged: (PanelLanguage language) =>
      prefs.setString('flutter_dio_inspector.language', language.name),
);
```

`fromCode` is tolerant: a missing key, an empty string or a code written by a newer version falls back
to English instead of throwing on startup. The callback runs after the panel has already repainted,
and anything it throws is swallowed — a failed settings write never breaks the switch. If your app
changes its own locale at runtime, move the panel with it the same way:
`panelLanguage.language = PanelLanguage.fromCode(newCode)`.

## Unread tracking

The ball badge is an **unread counter**, not an error counter. Rows that are still unread carry a red
`NEW` tag on their top-left corner.

```
new requests arrive   →  badge counts up, rows are tagged NEW
open the panel        →  rows keep their NEW tag
open one entry        →  that row's tag clears
close the panel       →  every tag clears, badge is 0
next request arrives  →  badge starts again at 1
```

The watermark moves on **close**, not on open. Advancing it on open would wipe the tags at the exact
moment you opened the panel to look for them. Opening an entry counts as an explicit "seen", so that
row clears immediately rather than waiting for the panel to close.

Failure counts are surfaced separately: the header shows `N failed` (`N 失败` in Chinese), and failed
rows are colour-coded.

## How it hooks in

`DioNetworkPanelInterceptor` is an ordinary `Interceptor`. **Add it first.**

dio runs request, response *and* error interceptors in list order — it does not reverse the order for
the response path the way most middleware stacks do (`dio/src/dio_mixin.dart`). Two consequences:

- A request that an earlier interceptor rejects never reaches a later interceptor's `onRequest`, so an
  inspector added last silently misses those requests.
- `onError` is attached to the end of the whole chain, so it fires for every interceptor even when the
  failure happened before their `onRequest` ran.

Because it runs first, `onRequest` sees the request *before* other interceptors have touched it. So
the terminal callbacks re-read the request side from the final `RequestOptions` — the same instance
flows through the chain, so by then it holds the headers and body that were actually sent. That is how
a header added by an auth interceptor still shows up in the panel.

A bug in the inspector must never break the request it is observing, so every hook is wrapped: if the
interceptor throws, the request continues and the failure is reported once via `debugPrint`.

## Known limitations

**A request rejected with `handler.reject(err)` stays pending forever (`···`).** dio completes that
call with an `InterceptorResultType.reject` *value* rather than a Future error, and its error handlers
are attached with `catchError` — so when `callFollowingErrorInterceptor` is left at its `false`
default, no `onError` runs anywhere and there is no hook that could record the outcome. Pass
`handler.reject(err, true)` if you want the panel to see it; the detail view says so at the point
where you would notice.

**No time-to-first-byte.** dio does not expose it. Reporting the total duration under a TTFB label
would be a lie, so the field does not exist.

**Response size is the decoded body size, not the wire size.** gzip means they differ.

**Multipart bodies are summarised**, not serialised: field values, file names and sizes. Reading the
file streams to serialise them would consume the payload the adapter is about to send.

**Streamed responses are not read.** With `ResponseType.stream` the panel records size and MIME type
only — touching the stream would take the data away from your own code. The same applies to a `Stream`
request body.

**Binary bodies are recorded by size only** — reading them as text would throw.

**Expand-all on a very large document builds every row at once.** The tree is a `Column`, not a
virtualised list, so fully opening a 32 KB document renders a few thousand rows in a single frame.
Collapsed nodes cost nothing to render, which is why the default depth is two rather than everything.

**The panel's own traffic is not special-cased.** If it shows up, use `ignore`.

## Testing

The core is pure Dart and the interceptor runs against a fake `HttpClientAdapter`, so the whole thing
is testable without a device or a network:

```sh
flutter test
```

127 tests cover:

- the ring buffer, byte-budget degradation, UTF-8-safe truncation, cURL quoting, unread-count
  invariants, and opt-in header redaction;
- the interceptor's behaviour for success, 404, each timeout, cancellation and connection failure,
  plus the body shapes that must not be consumed;
- the widget flow — badge, `NEW` markers, back navigation, filters, copy toast, collapsible sections,
  JSON folding and highlighting, the language switch and its persistence hook.

## Releasing

Pushing a `v*` tag publishes to pub.dev and cuts a GitHub Release:

```sh
# bump `version:` in pubspec.yaml first
git tag v0.1.1 && git push origin v0.1.1
```

The workflow is `.github/workflows/release.yml` inside this package, and it assumes **this directory
is the repository root** — GitHub only reads workflows from a repo root, so it takes effect when
`flutter_dio_inspector` is pushed as its own repository. The demo app stays outside it. It refuses to run when
the tag and the pubspec `version` disagree, so a typo fails in seconds instead of publishing the wrong
version under a tag that says something else.

Two things the workflow cannot do for you, once:

1. **Publish the first version by hand.** Automated publishing can only add *new* versions to a
   package that already exists: `dart pub publish`.
2. **Enable trusted publishing** at <https://pub.dev/packages/flutter_dio_inspector/admin> → *Automated
   publishing*, with repository `<owner>/<repo>` and tag pattern `v{{version}}`. Nothing to store as
   a secret: authentication is a short-lived OIDC token that GitHub signs and pub.dev exchanges, so
   there is no key to leak or rotate.

## License

MIT.
