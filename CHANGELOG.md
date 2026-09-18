# Changelog

## 1.0.0 — 2026-09-18

- First tagged release. Same feature set as 0.1.0, versioned for
  git-tag consumption (`ref: v1.0.0`).

## 0.1.0 — 2026-09-17

- Port LiveChat Android's URL contract and queue-based JavaScript bridge to Dart.
- Add initialize, preload, show, hide, customer identity, sign-out and destroy.
- Keep one native WebView mounted while the full-screen chat is hidden.
- Add embedded view alternative, message/error/link/picker callbacks,
  persistent sign-out replay, stale reload and loading/retry overlays.
- Add Android file selection through file_selector and an Android/iOS example.
- Add URL, identity ordering, lifecycle, navigation, retry and bridge tests.
