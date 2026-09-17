# LiveChat Flutter SDK

Dart port of the existing **LiveChat Android SDK**, using `webview_flutter` on
Android and iOS. The merchant's own chat page provides the conversation UI.
This package supplies the persistent WebView, JavaScript bridge, member identity,
sign-out, message callbacks, loading/retry UI, and attachment picker.

The URL and `ready` / `message` / `error` events match the Android source.
No Swift/Kotlin SDK wrapper or dependency on the Android repository is required.

## Requirements

- Flutter 3.41+ / Dart 3.11+.
- Android API 24+ (the original native Android SDK supported API 23).
- iOS 13+ for the package dependencies; the included example targets **iOS 15+**
  for the Xcode installed when it was built.
- An existing deployment and merchant public ID. The SDK does not include a server.
- Android/iOS only. Web and desktop are not supported by this package.

## Add to an app

```yaml
dependencies:
  livechat_flutter:
    path: ../livechat_flutter
```

In the Android host's `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

Set `minSdk = 24` or higher in `android/app/build.gradle.kts`.
Use HTTPS in production. A development HTTP server additionally needs the host's
Android cleartext / iOS ATS configuration. The example does not enable global
cleartext traffic.

## Initialize and install the persistent host

Initialize once at app startup. **Await the asynchronous methods.**

```dart
WidgetsFlutterBinding.ensureInitialized();
await LiveChat.initialize(
  baseUrl: 'https://chat.example.com',
  merchantPublicId: '01JMERCHANT',
);
runApp(MaterialApp(
  builder: (context, child) => LiveChatHost(child: child!),
  home: const HomePage(),
));
```

Mount exactly one `LiveChatHost`. It keeps the same native WebView mounted off
screen after the chat closes, so message callbacks remain connected. Its child
must fill the app's available space, as the Navigator supplied by MaterialApp does.

Once the first frame has mounted the host, preload if you need unread events
before the visitor first opens the chat:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
  await LiveChat.preload();
});
```

Open from a context inside your current route:

```dart
await LiveChat.show(context);
LiveChat.hide();
```

The full-screen chat includes a Close button and resizes above the keyboard.
Android system back closes it through the current route's local history.
`show()` finishes once the screen is opened; it does not wait until dismissal.
It presents above the Navigator rather than pushing a new route. Close the chat
before performing unrelated app navigation programmatically.

A chat older than one minute is reloaded when reopened, matching Android's
refresh behavior for merchant availability/settings.

## Signed-in members and sign-out

```dart
await LiveChat.setCustomerInfo(
  externalId: 'member-123',
  name: 'Member Customer',
  email: 'member@example.test',
  customParams: {'plan': 'vip'},
);

// Call and await from your app's own sign-out flow.
await LiveChat.signOutCustomer();
```

`externalId` is required. Identity is remembered in memory and applied when the
widget emits `ready`. Restore the current app member at startup after initialize.
A pending sign-out is saved per deployment/merchant and replayed **before** the
next identify call. A failed reset leaves the pending flag intact for retry.
Sign-out before initialization is a no-op, matching Android.

The widget's existing identity trust model is unchanged. This package does not
add server authentication. It never clears storage belonging to other WebViews.

## Callbacks

```dart
LiveChat.newMessageListener = (message, isChatShown) {
  if (!isChatShown) {
    // Update your unread badge.
  }
};
LiveChat.errorListener = (error) {
  // error.kind: ChatErrorKind.pageLoad or ChatErrorKind.widget.
};
LiveChat.urlHandler = (uri) async {
  // Return true if your app handled this URL.
  return false; // Fall back to the system's external URL handler.
};
LiveChat.filePickerNotFoundListener = () {
  // Display an attachment picker error.
};
```

Callbacks run on Flutter's UI isolate. The SDK forwards the widget's message
payload, just like Android; the widget decides which messages it emits.
`isChatShown` is false when hidden or the application is not resumed.
No offline push is included: terminated apps need a separate FCM/APNs integration.

Only HTTP(S), mailto, tel and sms links are launched by default. Other main-frame
navigation is blocked to keep unrelated content out of the bridged WebView.

## Loading and errors

```dart
LiveChat.loadErrorTitle = 'Chat unavailable';
LiveChat.loadErrorMessage = 'Check your connection and try again.';
LiveChat.loadErrorRetryTitle = 'Retry';
```

The loading overlay remains until widget readiness and pending identity work
complete. Main-page network/HTTP failures show Retry; resource failures do not
replace the chat. A 45-second readiness timeout prevents an endless spinner.
Widget errors are delivered to the callback and let the widget show its own UI.

## Attachments

Android file inputs use `file_selector`, including multiple selection and
accept-type filters. Canceling returns an empty selection. iOS uses WKWebView's
system picker. No hand-written native picker code is required.

For direct camera capture or app-specific selection, override the Android hook:

```dart
LiveChat.fileSelector = (params) async {
  // Open your picker and return file:// or content:// URI strings.
  return <String>[];
};
```

The default offers existing files; it does not implement HTML capture requests
as a dedicated camera action. The host supplies any camera/microphone/photo
privacy descriptions and permissions required by its chosen capture flow.

## Embed instead of full-screen

`LiveChatView` is the counterpart of `LiveChatFragment`. Use it **instead of**
`LiveChatHost`, never alongside it:

```dart
Scaffold(
  body: LiveChatView(visible: supportTabIsSelected),
);
```

It starts the chat after mounting. Give it bounded space, keep it mounted in an
`IndexedStack` for unread events while on another tab, and update `visible`.
Use your tab/navigation controls for embedded mode rather than `show()`/`hide()`.
Only one view can own a native WebView. Unlike the Android SDK, this version does
not support moving a live chat between embedded and full-screen hosts.
Configure before mounting an embedded view; unmount it before changing deployment.

## Teardown

```dart
await LiveChat.destroy();
```

Stops the page, removes the bridge and releases the controller reference. The
configuration and current in-memory customer remain, so preload/show can start
again. Hiding alone deliberately does not destroy the chat. Call destroy before
permanently removing the host.

## Run the example

```sh
cd example
flutter pub get
flutter run \
  --dart-define=LIVECHAT_BASE_URL=https://your-chat-host.example \
  --dart-define=LIVECHAT_MERCHANT_ID=YOUR_MERCHANT_PUBLIC_ID
```

The example defaults to the supplied Munchy deployment:

- Base URL: `https://chat.example.com`
- Merchant ID: `01JMERCHANT`
- Final URL: `https://chat.example.com/widget/app/01JMERCHANT`

Run `cd example && flutter run` to use these defaults. The dart-defines above
override them for another deployment. The reusable SDK itself has no hard-coded
merchant. The example contains open/preload/destroy, member identity, sign-out,
unread count and error status controls.

## Verify

```sh
flutter pub get
flutter analyze
flutter test
node tool/bridge_test.mjs
cd example
flutter test
flutter build apk --debug
flutter build ios --simulator --debug
```

See `PORTING_NOTES.md` for source provenance, platform differences and validation
results. The package is private (`publish_to: none`); no repository, release or
pub.dev publication is created by this port.
