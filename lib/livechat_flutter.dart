library;

import 'dart:async';
import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'src/bridge.dart';
import 'src/identity.dart';
import 'src/models.dart';
export 'src/models.dart';

/// Flutter counterpart of the LiveChat Android singleton.
/// Mount one [LiveChatHost] (full-screen mode) or [LiveChatView] (embedded mode).
abstract final class LiveChat {
  static _ChatSession? _session;
  static final ValueNotifier<int> _configuration = ValueNotifier(0);
  static Object? _host;
  static LocalHistoryEntry? _history;
  static void Function(ChatMessage message, bool isChatShown)?
  newMessageListener;
  static void Function(ChatError error)? errorListener;
  static FutureOr<bool> Function(Uri url)? urlHandler;
  static VoidCallback? filePickerNotFoundListener;

  /// Override to support capture or a custom attachment picker on Android.
  static Future<List<String>> Function(FileSelectorParams params)? fileSelector;
  static String loadErrorTitle = 'Chat unavailable';
  static String loadErrorMessage = 'Check your connection and try again.';
  static String loadErrorRetryTitle = 'Retry';
  static bool get isInitialized => _session != null;
  static _ChatSession get _required =>
      _session ??
      (throw StateError('Call and await LiveChat.initialize() first.'));

  static Future<void> initialize({
    required String baseUrl,
    required String merchantPublicId,
  }) async {
    final url = chatUrlOf(baseUrl, merchantPublicId);
    if (_session?.url == url) return;
    hide();
    await _session?.shutdown();
    _session = _ChatSession(url);
    _configuration.value++;
  }

  /// Starts the page without displaying it. A mounted host keeps it alive.
  static Future<void> preload() async {
    if (_host == null) {
      throw StateError('Mount LiveChatHost or LiveChatView first.');
    }
    await _required.start();
  }

  /// Opens above the app. The route's local history handles system back.
  static Future<void> show(BuildContext context) async {
    final route = ModalRoute.of(context);
    if (route == null) {
      throw StateError('show() needs a context inside a route.');
    }
    await preload();
    if (!context.mounted) return;
    if (_history == null) {
      _history = LocalHistoryEntry(
        onRemove: () {
          _history = null;
          _session?.setShown(false);
          _session?.dismissKeyboard();
        },
      );
      route.addLocalHistoryEntry(_history!);
    }
    _required.setShown(true);
    await _required.reloadIfStale();
  }

  static void hide() {
    _history?.remove();
    _history = null;
    _session?.setShown(false);
    _session?.dismissKeyboard();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  static Future<void> setCustomerInfo({
    required String externalId,
    String? name,
    String? email,
    Map<String, String> customParams = const {},
  }) => _required.identity.identify(
    externalId: externalId,
    name: name,
    email: email,
    customParams: customParams,
  );

  /// Await this in your sign-out flow so the pending reset reaches disk.
  static Future<void> signOutCustomer() async {
    await _session?.identity.signOut();
  }

  /// Releases the current page; configuration and member identity remain.
  static Future<void> destroy() async {
    hide();
    await _session?.shutdown();
  }
}

class _ChatSession extends ChangeNotifier {
  _ChatSession(this.url) {
    final prefs = SharedPreferencesAsync();
    final key =
        'livechat_flutter.pending_sign_out.${Uri.encodeComponent(url.toString())}';
    identity = ChatIdentity(
      readPending: () async => await prefs.getBool(key) ?? false,
      writePending: (value) => prefs.setBool(key, value),
      evaluate: (script) async {
        final current = controller;
        if (current == null || !identity.ready) {
          throw StateError('Chat is not ready');
        }
        await current.runJavaScript(script);
      },
    );
  }
  final Uri url;
  late final ChatIdentity identity;
  WebViewController? controller;
  Future<void>? _starting;
  bool shown = false, foreground = true, loading = true;
  ChatError? failure;
  final Stopwatch _age = Stopwatch();
  Timer? _timeout;
  int _generation = 0;

  void setShown(bool value) {
    shown = value;
    notifyListeners();
  }

  /// Closes the soft keyboard raised by the WebView's focused HTML input.
  /// FocusManager only handles Flutter focus, so blur the active DOM element
  /// and hide the platform IME explicitly when the chat is dismissed.
  void dismissKeyboard() {
    try {
      controller?.runJavaScript(
        'if (document.activeElement && document.activeElement.blur) { '
        'document.activeElement.blur(); }',
      );
    } catch (_) {
      /* Controller not ready; nothing focused to blur. */
    }
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  Future<void> start() => _starting ??= _start();
  Future<void> _start() async {
    final generation = ++_generation;
    try {
      PlatformWebViewControllerCreationParams params =
          const PlatformWebViewControllerCreationParams();
      if (WebViewPlatform.instance is WebKitWebViewPlatform) {
        params = WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
          mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
        );
      }
      final web = WebViewController.fromPlatformCreationParams(params);
      controller = web;
      await web.setJavaScriptMode(JavaScriptMode.unrestricted);
      await web.setBackgroundColor(Colors.white);
      await web.enableZoom(false);
      await web.addJavaScriptChannel(
        'LiveChatFlutter',
        onMessageReceived: (message) {
          if (generation == _generation) {
            unawaited(_event(message.message, generation));
          }
        },
      );
      await web.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (generation == _generation) _beginLoading();
          },
          onPageFinished: (_) async {
            if (generation != _generation || failure != null) return;
            try {
              await web.runJavaScript(bootstrapScript);
            } catch (error) {
              if (generation == _generation) _fail(error.toString());
            }
          },
          onWebResourceError: (error) {
            if (generation == _generation && error.isForMainFrame == true) {
              _fail(error.description);
            }
          },
          onHttpError: (error) {
            if (generation == _generation && error.request?.uri == url) {
              _fail(
                'The chat page answered with HTTP ${error.response?.statusCode}.',
              );
            }
          },
          onNavigationRequest: (request) async {
            if (generation != _generation) return NavigationDecision.prevent;
            if (!request.isMainFrame || Uri.tryParse(request.url) == url) {
              return NavigationDecision.navigate;
            }
            final target = Uri.tryParse(request.url);
            if (target != null &&
                [
                  'https',
                  'http',
                  'mailto',
                  'tel',
                  'sms',
                ].contains(target.scheme)) {
              try {
                final handled =
                    await LiveChat.urlHandler?.call(target) ?? false;
                if (!handled) {
                  await launchUrl(target, mode: LaunchMode.externalApplication);
                }
              } catch (error) {
                LiveChat.errorListener?.call(
                  ChatError(ChatErrorKind.widget, error.toString()),
                );
              }
            }
            return NavigationDecision.prevent;
          },
        ),
      );
      if (web.platform is AndroidWebViewController) {
        final android = web.platform as AndroidWebViewController;
        await android.setMediaPlaybackRequiresUserGesture(false);
        await android.setOnShowFileSelector((params) async {
          try {
            if (LiveChat.fileSelector != null) {
              return await LiveChat.fileSelector!(params);
            }
            final accept = params.acceptTypes
                .where((s) => s.isNotEmpty && s != '*/*')
                .toList();
            final mime = accept.where((s) => s.contains('/')).toList();
            final extensions = accept
                .where((s) => s.startsWith('.'))
                .map((s) => s.substring(1))
                .toList();
            final groups = accept.isEmpty
                ? <XTypeGroup>[]
                : [
                    XTypeGroup(
                      label: 'Attachments',
                      mimeTypes: mime.isEmpty ? null : mime,
                      extensions: extensions.isEmpty ? null : extensions,
                    ),
                  ];
            final files = params.mode == FileSelectorMode.openMultiple
                ? await openFiles(acceptedTypeGroups: groups)
                : [
                    if (await openFile(acceptedTypeGroups: groups)
                        case final XFile file)
                      file,
                  ];
            return files.map((file) => Uri.file(file.path).toString()).toList();
          } catch (_) {
            LiveChat.filePickerNotFoundListener?.call();
            return <String>[];
          }
        });
      }
      if (generation != _generation) return;
      notifyListeners();
      await reload();
    } catch (error) {
      if (generation == _generation) {
        _starting = null;
        _fail(error.toString());
      }
      rethrow;
    }
  }

  void _beginLoading() {
    identity.ready = false;
    failure = null;
    loading = true;
    _age
      ..reset()
      ..start();
    _timeout?.cancel();
    _timeout = Timer(
      const Duration(seconds: 45),
      () => _fail('The chat timed out. Try again.'),
    );
    notifyListeners();
  }

  Future<void> reload() async {
    _beginLoading();
    try {
      await controller?.loadRequest(url);
    } catch (error) {
      _fail(error.toString());
    }
  }

  Future<void> reloadIfStale() async {
    if (_age.elapsed >= const Duration(minutes: 1)) await reload();
  }

  void _fail(String description) {
    _timeout?.cancel();
    loading = false;
    identity.ready = false;
    failure = ChatError(ChatErrorKind.pageLoad, description);
    notifyListeners();
    LiveChat.errorListener?.call(failure!);
  }

  Future<void> _event(String raw, int generation) async {
    try {
      final event = jsonDecode(raw);
      if (event is! Map<String, dynamic>) return;
      switch (event['type']) {
        case 'ready':
          if (failure != null) return;
          await identity.onReady();
          if (generation != _generation) return;
          _timeout?.cancel();
          loading = false;
          notifyListeners();
        case 'message':
          final data = event['message'];
          if (data is Map<String, dynamic>) {
            LiveChat.newMessageListener?.call(
              ChatMessage.fromJson(data),
              shown && foreground,
            );
          }
        case 'error':
          _timeout?.cancel();
          loading = false;
          notifyListeners();
          LiveChat.errorListener?.call(
            ChatError(
              ChatErrorKind.widget,
              event['description'] is String
                  ? event['description'] as String
                  : 'Widget error',
            ),
          );
      }
    } on FormatException {
      /* Ignore malformed bridge messages. */
    } catch (error) {
      _fail(error.toString());
    }
  }

  Future<void> shutdown() async {
    ++_generation;
    _timeout?.cancel();
    identity.ready = false;
    final old = controller;
    controller = null;
    _starting = null;
    shown = false;
    notifyListeners();
    if (old != null) {
      await old.removeJavaScriptChannel('LiveChatFlutter');
      // webview_flutter has no explicit controller dispose API. Unmount the
      // view and replace its page to stop scripts before releasing the reference.
      await old.loadHtmlString('<html><body></body></html>');
    }
  }
}

/// Install in MaterialApp.builder. Its WebView remains mounted while hidden.
class LiveChatHost extends StatefulWidget {
  const LiveChatHost({
    super.key,
    required this.child,
    this.title = 'Live chat',
  });
  final Widget child;
  final String title;
  @override
  State<LiveChatHost> createState() => _LiveChatHostState();
}

class _LiveChatHostState extends State<LiveChatHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    if (LiveChat._host != null) {
      throw StateError('Mount only one LiveChat host/view at a time.');
    }
    LiveChat._host = this;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    LiveChat._session?.foreground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (identical(LiveChat._host, this)) {
      LiveChat.hide();
      LiveChat._host = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: LiveChat._configuration,
    builder: (context, _, child) {
      final session = LiveChat._session;
      if (session == null) return widget.child;
      return ListenableBuilder(
        listenable: session,
        builder: (context, _) => Overlay.wrap(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ExcludeFocus(
                excluding: session.shown,
                child: ExcludeSemantics(
                  excluding: session.shown,
                  child: widget.child,
                ),
              ),
              Offstage(
                offstage: !session.shown,
                child: ExcludeFocus(
                  excluding: !session.shown,
                  child: Scaffold(
                    appBar: AppBar(
                      title: Text(widget.title),
                      automaticallyImplyLeading: false,
                      leading: IconButton(
                        tooltip: 'Close chat',
                        onPressed: LiveChat.hide,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                    body: SafeArea(child: _ChatBody(session: session)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Embedded alternative to LiveChatHost. Keep this widget mounted (for example
/// in an IndexedStack) and update visible as its tab/route changes. Do not mount
/// it alongside LiveChatHost: a WebView controller has exactly one visual owner.
class LiveChatView extends StatefulWidget {
  const LiveChatView({super.key, this.visible = true});
  final bool visible;
  @override
  State<LiveChatView> createState() => _LiveChatViewState();
}

class _LiveChatViewState extends State<LiveChatView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    if (LiveChat._host != null) {
      throw StateError('Mount only one LiveChat host/view at a time.');
    }
    LiveChat._host = this;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await LiveChat.preload();
      } catch (_) {
        /* Session displays its load error. */
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    LiveChat._session?.foreground = state == AppLifecycleState.resumed;
  }

  @override
  void didUpdateWidget(LiveChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      unawaited(LiveChat._required.reloadIfStale());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (identical(LiveChat._host, this)) {
      LiveChat._host = null;
      LiveChat._session?.shown = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = LiveChat._required;
    session.shown =
        widget.visible && (ModalRoute.of(context)?.isCurrent ?? true);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Offstage(
        offstage: !widget.visible,
        child: ExcludeFocus(
          excluding: !widget.visible,
          child: SafeArea(child: _ChatBody(session: session)),
        ),
      ),
    );
  }
}

class _ChatBody extends StatelessWidget {
  const _ChatBody({required this.session});
  final _ChatSession session;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (session.controller case final WebViewController controller)
        WebViewWidget(key: ObjectKey(controller), controller: controller),
      if (session.loading || session.failure != null)
        Positioned.fill(
          child: ColoredBox(
            color: Colors.white,
            child: AbsorbPointer(
              absorbing: session.failure == null,
              child: Center(
                child: session.failure == null
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              LiveChat.loadErrorTitle,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              LiveChat.loadErrorMessage,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: () async {
                                if (session.controller == null) {
                                  try {
                                    await session.start();
                                  } catch (_) {}
                                } else {
                                  await session.reload();
                                }
                              },
                              child: Text(LiveChat.loadErrorRetryTitle),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
    ],
  );
}
