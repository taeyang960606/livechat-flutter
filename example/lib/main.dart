// Unified sample — one home screen with every presentation mode, so you can see
// the "Activity" (full screen) and "Fragment" (embedded dialog / sheet) styles
// side by side without switching run targets.
//
// A LiveChat session has exactly one visual owner at a time, so this app does
// NOT mount a global LiveChatHost. Instead each mode mounts a LiveChatView only
// while it is on screen:
//   - Full screen (Activity)  -> a pushed route whose body is a LiveChatView
//   - Dialog (Fragment)       -> a LiveChatView inside a Material Dialog
//   - Bottom sheet            -> a LiveChatView inside a modal bottom sheet
//
// Trade-off vs the LiveChat.show() + LiveChatHost path: unread only counts once
// the chat has been opened at least once (the WebView is created on first open),
// because nothing is mounted to keep it alive beforehand.
//
// Run:
//   flutter run
//   flutter run --dart-define=LIVECHAT_BASE_URL=https://your.deployment \
//               --dart-define=LIVECHAT_MERCHANT_ID=yourMerchantId

import 'package:flutter/material.dart';
import 'package:livechat_flutter/livechat_flutter.dart';

const baseUrl = String.fromEnvironment(
  'LIVECHAT_BASE_URL',
  defaultValue: 'https://chat.example.com',
);
const merchantId = String.fromEnvironment(
  'LIVECHAT_MERCHANT_ID',
  defaultValue: '01JMERCHANT',
);

final unread = ValueNotifier<int>(0);
final status = ValueNotifier<String>('Ready');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (baseUrl.isNotEmpty && merchantId.isNotEmpty) {
    await LiveChat.initialize(baseUrl: baseUrl, merchantPublicId: merchantId);
  }
  LiveChat.newMessageListener = (message, isShown) {
    if (!isShown) unread.value++;
    status.value = '${message.senderType}: ${message.body}';
  };
  LiveChat.errorListener = (error) => status.value = error.description;
  LiveChat.filePickerNotFoundListener = () =>
      status.value = 'Could not open the file picker';
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LiveChat example',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const HomePage(),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      status.value = error.toString();
    }
  }

  void _openFullScreen(BuildContext context) {
    unread.value = 0;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const FullScreenChatPage()),
    );
  }

  Future<void> _openDialog(BuildContext context) {
    unread.value = 0;
    return showDialog<void>(
      context: context,
      builder: (_) => const LiveChatDialog(),
    );
  }

  Future<void> _openSheet(BuildContext context) {
    unread.value = 0;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.9,
        child: ChatFrame(showHeaderClose: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = LiveChat.isInitialized;
    return Scaffold(
      appBar: AppBar(title: const Text('LiveChat Flutter')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'One SDK, three presentations.',
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 16),
            if (!ready)
              const Text(
                'Run with LIVECHAT_BASE_URL and LIVECHAT_MERCHANT_ID '
                'dart-defines. See README.',
              ),
            const SizedBox(height: 8),
            ValueListenableBuilder<int>(
              valueListenable: unread,
              builder: (context, count, _) => FilledButton.icon(
                icon: const Icon(Icons.fullscreen),
                label: Text('Full screen — Activity ($count unread)'),
                onPressed: ready ? () => _openFullScreen(context) : null,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Dialog — Fragment'),
              onPressed: ready ? () => _openDialog(context) : null,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.vertical_align_bottom),
              label: const Text('Bottom sheet'),
              onPressed: ready ? () => _openSheet(context) : null,
            ),
            const Divider(height: 32),
            OutlinedButton(
              onPressed: ready
                  ? () => _guard(() async {
                      await LiveChat.setCustomerInfo(
                        externalId: 'demo-member-123',
                        name: 'Demo Member',
                        email: 'member@example.test',
                        customParams: {'plan': 'vip'},
                      );
                      status.value = 'Member identity saved';
                    })
                  : null,
              child: const Text('Identify demo member'),
            ),
            OutlinedButton(
              onPressed: ready
                  ? () => _guard(() async {
                      await LiveChat.signOutCustomer();
                      unread.value = 0;
                      status.value = 'Signed out';
                    })
                  : null,
              child: const Text('Sign out'),
            ),
            TextButton(
              onPressed: () => _guard(LiveChat.destroy),
              child: const Text('Destroy chat'),
            ),
            const Divider(height: 32),
            ValueListenableBuilder<String>(
              valueListenable: status,
              builder: (_, text, __) => Text(text),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen presentation — the Android Activity analogue. A pushed route
/// whose body is the embedded chat; the system back button pops it.
class FullScreenChatPage extends StatelessWidget {
  const FullScreenChatPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Live chat'),
      leading: IconButton(
        tooltip: 'Close',
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    ),
    body: const SafeArea(child: LiveChatView()),
  );
}

/// Dialog presentation — the Android DialogFragment analogue.
class LiveChatDialog extends StatelessWidget {
  const LiveChatDialog({super.key});
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
      child: const ChatFrame(),
    ),
  );
}

/// A titled header plus the embedded [LiveChatView]. The view owns the session
/// while on screen and releases it when dismissed.
class ChatFrame extends StatelessWidget {
  const ChatFrame({super.key, this.showHeaderClose = true});
  final bool showHeaderClose;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 52,
        child: Row(
          children: [
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                'Live chat',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
            if (showHeaderClose)
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
          ],
        ),
      ),
      const Divider(height: 1),
      const Expanded(child: LiveChatView()),
    ],
  );
}
