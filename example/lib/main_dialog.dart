// Dialog-style sample — the Flutter analogue of an Android DialogFragment.
//
// It shows the same LiveChat conversation inside a modal Dialog (and a bottom
// sheet), instead of the full-screen presentation in main.dart.
//
// Why this is a separate entrypoint: a LiveChat session has exactly one visual
// owner at a time. main.dart mounts a LiveChatHost for the full-screen show()
// path; here we do NOT mount a host, and instead mount a LiveChatView inside
// the dialog while it is open, releasing it when the dialog closes.
//
// Run:
//   flutter run -t lib/main_dialog.dart \
//     --dart-define=LIVECHAT_BASE_URL=https://your.deployment \
//     --dart-define=LIVECHAT_MERCHANT_ID=yourMerchantId
//
// Note: because the chat is only mounted while the dialog is open, background
// unread counting (a reply arriving with the dialog closed) is not shown here —
// that pattern uses the always-mounted LiveChatHost in main.dart.

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

final status = ValueNotifier<String>('Ready');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (baseUrl.isNotEmpty && merchantId.isNotEmpty) {
    await LiveChat.initialize(baseUrl: baseUrl, merchantPublicId: merchantId);
  }
  LiveChat.newMessageListener = (message, isShown) {
    status.value = '${message.senderType}: ${message.body}';
  };
  LiveChat.errorListener = (error) => status.value = error.description;
  LiveChat.filePickerNotFoundListener = () =>
      status.value = 'Could not open the file picker';
  runApp(const DialogExampleApp());
}

class DialogExampleApp extends StatelessWidget {
  const DialogExampleApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LiveChat dialog example',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const DialogHomePage(),
  );
}

class DialogHomePage extends StatelessWidget {
  const DialogHomePage({super.key});

  Future<void> _openDialog(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const LiveChatDialog(),
  );

  Future<void> _openSheet(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.9,
      child: _ChatFrame(showHeaderClose: false),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('LiveChat dialog')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'The chat shown in a dialog and a bottom sheet.',
            style: TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 16),
          if (!LiveChat.isInitialized)
            const Text(
              'Run with LIVECHAT_BASE_URL and LIVECHAT_MERCHANT_ID '
              'dart-defines. See README.',
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Open chat dialog'),
            onPressed: LiveChat.isInitialized
                ? () => _openDialog(context)
                : null,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.vertical_align_bottom),
            label: const Text('Open chat bottom sheet'),
            onPressed: LiveChat.isInitialized
                ? () => _openSheet(context)
                : null,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: LiveChat.isInitialized
                ? () async {
                    await LiveChat.setCustomerInfo(
                      externalId: 'demo-member-123',
                      name: 'Demo Member',
                      email: 'member@example.test',
                      customParams: {'plan': 'vip'},
                    );
                    status.value = 'Member identity saved';
                  }
                : null,
            child: const Text('Identify demo member'),
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

/// The LiveChat conversation framed as a Material dialog.
class LiveChatDialog extends StatelessWidget {
  const LiveChatDialog({super.key});
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
      child: const _ChatFrame(),
    ),
  );
}

/// A titled header plus the embedded [LiveChatView]. The view is the session's
/// single owner while this frame is on screen, and is released when it leaves.
class _ChatFrame extends StatelessWidget {
  const _ChatFrame({this.showHeaderClose = true});
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
