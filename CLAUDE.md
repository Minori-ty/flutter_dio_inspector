# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`flutter_dio_inspector` is a pub.dev package (not an app): an in-app network panel for
[Dio](https://pub.dev/packages/dio). A draggable floating ball with an unread badge opens a
full-screen inspector for requests, responses, headers, bodies and cURL export.

One runtime dependency (`dio`), no native code, no codegen, no state-management package. The
`example/` directory is a minimal runnable demo (platform folders are not committed — `flutter
create .` inside it to run).

## Commands

```sh
flutter pub get          # install dependencies
flutter analyze          # lint (flutter_lints)
flutter test             # run the full suite (~127 tests)
flutter test test/core_test.dart   # run one file
flutter test test/core_test.dart --plain-name 'utf8ByteLength'  # run one group/test
```

There is no build step. Tests are pure Dart / widget tests — the interceptor runs against a fake
`HttpClientAdapter` (`test/interceptor_test.dart::_FakeAdapter`), so nothing needs a device or
network.

Releasing is tag-driven (see `.github/workflows/release.yml`): bump `version:` in `pubspec.yaml`,
then `git tag v0.1.1 && git push origin v0.1.1`. The workflow assumes this directory is the repo
root.

## Architecture

The library is layered so that everything testable stays pure Dart and only the top layer touches
Flutter or dio:

```
lib/src/core/      Pure Dart, no dio/Flutter imports — the part unit-tested in isolation.
lib/src/intercept/ DioNetworkPanelInterceptor — the only code that knows dio.
lib/src/store/     NetworkStore — a ChangeNotifier over the core buffer.
lib/src/i18n/      PanelLanguage / PanelLanguageController / PanelStrings.
lib/src/ui/        Flutter widgets (ball, list, detail, JSON tree).
lib/flutter_dio_inspector.dart   The public surface (explicit `export ... show` lists).
```

**Data flow.** `DioNetworkPanelInterceptor` records a request's start via `store.begin()`, stashes
the returned entry id in `RequestOptions.extra` (under `DioNetworkPanelInterceptor.entryIdKey`, so
it survives `copyWith`), then calls `store.patch(id, …)` from `onResponse`/`onError`. `NetworkStore`
holds a `NetworkEntryBuffer` and `notifyListeners()` on change; the widgets rebuild via
`ListenableBuilder`. `NetworkEntry` is immutable — every update is a new instance, which is what
makes the store's change-detection cheap.

**Entry id.** Carried in `RequestOptions.extra` rather than a side table on purpose: an interceptor
that replaces the options object would otherwise orphan the entry. The interceptor treats "no entry
id" in the terminal callbacks as normal, not a bug (see interceptor ordering below).

**Eviction policy lives entirely in `NetworkEntryBuffer`** (`core/buffer.dart`), which the store is a
thin wrapper over. Two independent limits — `maxEntries` (count) and `maxBytes` (bytes of stored
body *previews*, not transferred payload). The newest entry is never evicted; if one body exceeds
the whole byte budget, its preview is dropped (`BodySnapshot.withoutPreview()`) while metadata
survives.

**Body capture.** `BodySnapshot` + `BodyKind` (`core/entry.dart`); `serializer.dart` turns payloads
into snapshots and `detectBodyKind` sniffs MIME/content. Streams and `ResponseBody` are recorded by
size only — reading them would consume data the caller's code needs. Multipart is summarised, never
serialised.

**i18n is not ARB/intl.** `PanelStrings` is one class with a Chinese/English ternary per string, so a
string added to one language and forgotten in the other shows up in a single diff. Strings are a
plain value (no `BuildContext`), keeping widgets testable without `MaterialApp`. `PanelLanguage` does
not read the platform locale or `MaterialApp.locale` — the panel's language is the team's choice,
not the device's.

**Unread tracking.** `_seenId` in `_DioNetworkPanelState` is a watermark that moves on panel
*close*, not open — advancing on open would clear the `NEW` markers at the moment you opened the
panel to find them. Opening a detail row is an explicit "seen" (`_openedIds` in
`_NetworkPanelPageState`). The badge and per-row markers both derive from `unseenIds`/
`countUnseen` (`core/unseen.dart`) so they can never disagree.

## Non-obvious invariants

- **Add the interceptor first.** dio runs request, response *and* error interceptors in list order —
  it does not reverse order for the response path. Added last, it silently misses requests that an
  earlier interceptor rejects; added first, `onRequest` runs before others touch the request, and the
  terminal callbacks re-read the request side from the final `RequestOptions` (the same instance that
  flowed through the chain, so headers added by later interceptors still show up).

- **Every interceptor hook is wrapped in `_safely`** so a bug in the inspector never breaks the
  request it observes; the first failure is `debugPrint`-ed once.

- **`NetworkEntry.copyWith` treats `null` as "keep the existing value".** The interceptor relies on
  this for `failureKind`/`failureLabel`: the entry starts null and a success path passes `null` to
  keep it null.

- **Redaction is applied in `NetworkStore.begin`/`patch`, not at the call site.** Nothing is redacted
  by default (`defaultRedactedHeaders` is empty); opt in via
  `NetworkPanelConfig.redactedHeaders` (e.g. `sensitiveHeaders`).

- **`handler.reject(err)` without `callFollowingErrorInterceptor: true` leaves the entry pending
  forever** — dio completes that call with a value, not a Future error, so no `onError` fires. The
  detail view surfaces this as a pending note; it is a known limitation, not a bug to fix.

- **`NetworkStore._notify()` is synchronous on purpose.** An earlier microtask-deferred version was
  reverted — Flutter already coalesces multiple `markNeedsBuild` calls per frame, so deferring only
  added a frame of latency.

- **`PanelLanguageController` / `JsonTreeController` ownership**: a controller created by a widget is
  disposed by it (`_ownsLanguage` pattern); one passed in belongs to the caller. `JsonTreeController`
  keys expansion state by *path* (`$/0/2`, child indices), not JSON keys, since keys can contain any
  character. One controller per body in the detail page — request and response must not share one.

- **The panel carries its own palette** (`NetworkPanelTheme`, no theme parameter) so method/status
  colours mean the same thing across host apps; it follows only light/dark.
