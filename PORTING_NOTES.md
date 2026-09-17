# Porting notes

## Source

Requested target: `/Users/tanmeiyi/Documents/Flutter/livechat_flutter`.
Primary source: `/Users/tanmeiyi/Documents/Android/LiveChat`.
Source commit: `bcab413245d9825ecc1b31bacc8b66cf45307fc4` (clean working tree).

The cached Claude session `cse_01G9oqjxbNKX88fuUyfUjHhL` supplied the earlier
Option A decision: implement the thin SDK in Dart using webview_flutter.
Only the relevant available conversation segment was recovered; this is not a
claim that the entire historical conversation was retrieved. The current user
explicitly selected the Android project as the implementation reference.

## Mapping

| Android | Flutter |
| --- | --- |
| LiveChat singleton | LiveChat static API |
| ChatWindowBus / long-lived WebView | LiveChatHost / retained WebViewController and widget |
| ChatWindowActivity | Host full-screen panel, route local history for back |
| LiveChatFragment | LiveChatView, an alternative single-owner embedded host |
| LiveChatAndroid.postEvent | LiveChatFlutter.postMessage |
| SharedPreferences pending reset | SharedPreferencesAsync, deployment/merchant-scoped key |
| ACTION_GET_CONTENT file input | file_selector + Android setOnShowFileSelector |
| Android error strings | LiveChat.loadError* properties |

The bootstrap is directly adapted from ChatWindowView.kt. It preserves the
widget queue, idempotent subscriptions, and ready/message/error payloads.
The URL remains `baseUrl + /widget/app/ + merchantPublicId`.

## Deliberate differences

- Dart methods which perform I/O return Futures and should be awaited.
- Callbacks arrive on Flutter's UI isolate.
- A mounted host is required to retain the WebView while hidden. One native view
  owner is allowed; embedded/full-screen reparenting is not implemented.
- Full-screen opening uses an app-level panel and route local history, not a
  new native Android Activity or Flutter route.
- Input validation rejects invalid merchant IDs and ambiguous deployment URLs.
- Android minimum SDK is 24, as required by the selected WebView dependency.
- Pending reset operations are serialized, persisted per deployment/merchant,
  and cleared only after JavaScript evaluation succeeds.
- External URLs fall back to the system handler when urlHandler returns false;
  unrelated main-frame pages are never loaded in the bridged chat WebView.
- Adds a 45-second readiness timeout. Default file picker selects existing files;
  direct camera capture requires a host-supplied picker.
- Does not migrate an existing native SDK's pending-sign-out preference key.
  Existing host apps should sign out before switching SDK implementations.
- No offline push, server changes, publication, or Git remote was added.

## Validation (2026-09-17)

- Flutter 3.41.2 / Dart 3.11.0.
- 12 SDK unit/widget tests passed, including retained native-view identity across
  open/back, unread visibility, retry, URL handling and persisted identity ordering.
- 1 example smoke test passed.
- Node bridge test passed: queue, installed API calls, idempotence and event payloads.
- Android debug APK compiled successfully.
- iOS simulator compiled successfully for arm64 via xcodebuild.

On this machine, generic `flutter build ios --simulator` hit a Flutter/Xcode
multi-architecture packaging error. Building for the available arm64 simulator
succeeded with the equivalent command below (substitute an available simulator):

```sh
cd example/ios
xcodebuild -workspace Runner.xcworkspace -scheme Runner \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
```

Live readiness/open/close/reopen integration test passed on the iPhone 17 Pro
iOS simulator against the supplied Munchy deployment on 2026-09-17. The real
WKWebView reached widget readiness, then closed and reopened without a reload.
No messages, attachments or member identity were sent by the test.

Deployment: `https://chat.example.com`
Merchant: `01JMERCHANT`

The example uses these defaults; dart-defines can override them. The SDK has no
hard-coded merchant. Attachment selection, real operator/background messages,
Android device runtime and keyboard behavior still need separate device testing.
The unit/widget suite uses a fake WebView platform; the integration test uses
the real deployment.

## Dependency references

- https://pub.dev/packages/webview_flutter
- https://pub.dev/documentation/webview_flutter_android/latest/webview_flutter_android/AndroidWebViewController/setOnShowFileSelector.html
- https://pub.dev/packages/file_selector

Resolved versions are recorded in pubspec.lock.
