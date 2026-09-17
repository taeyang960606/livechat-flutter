# LiveChat example

Configured for the supplied deployment:

- Base URL: `https://chat.example.com`
- Merchant ID: `01JMERCHANT`

```sh
flutter pub get
flutter run
```

## Presentation modes

`lib/main.dart` (the default entrypoint) shows all three on one home screen —
tap a button to see each:

- **Full screen — Activity**: a pushed route whose body is a `LiveChatView`.
- **Dialog — Fragment**: a `LiveChatView` inside a Material `Dialog`.
- **Bottom sheet**: a `LiveChatView` inside a modal bottom sheet.

```sh
flutter run
```

Only one mode is on screen at a time — a LiveChat session has a single visual
owner, so this app mounts no global `LiveChatHost` and each mode mounts its own
`LiveChatView` while open. Because of that, unread only counts after the chat
has been opened once. For always-on background unread, use the `LiveChat.show()` +
always-mounted `LiveChatHost` pattern documented in the package README.
`lib/main_dialog.dart` is a standalone dialog-only variant of this sample.

Override with `--dart-define=LIVECHAT_BASE_URL=...` and
`--dart-define=LIVECHAT_MERCHANT_ID=...` for another deployment. Pass the origin
as the base URL, not the full `/widget/app/...` URL.

Passive live smoke test (opens chat, waits for ready, closes and reopens; sends
no messages or identity data):

```sh
flutter test integration_test/live_chat_test.dart -d DEVICE_ID
```
