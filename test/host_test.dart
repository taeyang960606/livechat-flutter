import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livechat_flutter/livechat_flutter.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class FakeWebPlatform extends WebViewPlatform {
  final controllers = <FakeController>[];
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = FakeController(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => FakeDelegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => FakeWidget(params);
}

class FakeController extends PlatformWebViewController {
  FakeController(super.params) : super.implementation();
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> enableZoom(bool enabled) async {}
  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {}
  JavaScriptChannelParams? bridge;
  final scripts = <String>[];
  final loads = <Uri>[];
  late FakeDelegate delegate;
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    bridge = params;
  }

  @override
  Future<void> removeJavaScriptChannel(String name) async {
    bridge = null;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    delegate = handler as FakeDelegate;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loads.add(params.uri);
  }

  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
  }

  void emit(String message) =>
      bridge!.onMessageReceived(JavaScriptMessage(message: message));
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class FakeDelegate extends PlatformNavigationDelegate {
  FakeDelegate(super.params) : super.implementation();
  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {}
  late PageEventCallback finish;
  late WebResourceErrorCallback error;
  late HttpResponseErrorCallback httpError;
  late NavigationRequestCallback navigation;
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finish = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    error = callback;
  }

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback callback) async {
    httpError = callback;
  }

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {
    navigation = callback;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class FakeWidget extends PlatformWebViewWidget {
  FakeWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) =>
      const SizedBox(key: ValueKey('native-chat'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeWebPlatform platform;
  setUp(() async {
    platform = FakeWebPlatform();
    WebViewPlatform.instance = platform;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await LiveChat.initialize(
      baseUrl: 'https://chat.test',
      merchantPublicId: 'merchant',
    );
  });
  tearDown(() async {
    await LiveChat.destroy();
    LiveChat.newMessageListener = null;
    LiveChat.errorListener = null;
    LiveChat.urlHandler = null;
  });
  testWidgets(
    'preload/show/back retain one native view and accurate unread visibility',
    (tester) async {
      late BuildContext routeContext;
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => LiveChatHost(child: child!),
          home: Builder(
            builder: (context) {
              routeContext = context;
              return const Scaffold(body: Text('Home'));
            },
          ),
        ),
      );
      await LiveChat.preload();
      await tester.pump();
      final web = platform.controllers.single;
      final native = find.byKey(
        const ValueKey('native-chat'),
        skipOffstage: false,
      );
      final element = tester.element(native);
      final visibility = <bool>[];
      LiveChat.newMessageListener = (_, shown) => visibility.add(shown);
      web.emit('{"type":"ready"}');
      await tester.pump();
      web.emit('{"type":"message","message":{"id":1}}');
      await LiveChat.show(routeContext);
      await tester.pump();
      web.emit('{"type":"message","message":{"id":2}}');
      await Navigator.of(routeContext).maybePop();
      await tester.pump();
      web.emit('{"type":"message","message":{"id":3}}');
      expect(visibility, [false, true, false]);
      expect(tester.element(native), same(element));
      expect(platform.controllers.length, 1);
      expect(web.loads.length, 1);
      expect(find.text('Home'), findsOneWidget);
      await LiveChat.destroy();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'subresource failures do not cover chat; main page failure offers retry',
    (tester) async {
      late BuildContext routeContext;
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => LiveChatHost(child: child!),
          home: Builder(
            builder: (context) {
              routeContext = context;
              return const Scaffold();
            },
          ),
        ),
      );
      await LiveChat.show(routeContext);
      await tester.pump();
      final web = platform.controllers.single;
      web.emit('{"type":"ready"}');
      await tester.pump();
      web.delegate.error(
        const WebResourceError(
          errorCode: -1,
          description: 'image',
          isForMainFrame: false,
        ),
      );
      await tester.pump();
      expect(find.text('Chat unavailable'), findsNothing);
      web.delegate.error(
        const WebResourceError(
          errorCode: -1,
          description: 'offline',
          isForMainFrame: true,
        ),
      );
      await tester.pump();
      expect(find.text('Chat unavailable'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(web.loads.length, 2);
      await LiveChat.destroy();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'external links stay out of the chat and reach host URL handler',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => LiveChatHost(child: child!),
          home: const Scaffold(),
        ),
      );
      await LiveChat.preload();
      final delegate = platform.controllers.single.delegate;
      Uri? opened;
      LiveChat.urlHandler = (uri) {
        opened = uri;
        return true;
      };
      expect(
        await delegate.navigation(
          const NavigationRequest(
            url: 'https://merchant.test/help',
            isMainFrame: true,
          ),
        ),
        NavigationDecision.prevent,
      );
      expect(opened.toString(), 'https://merchant.test/help');
      expect(
        await delegate.navigation(
          const NavigationRequest(
            url: 'https://chat.test/widget/app/merchant',
            isMainFrame: true,
          ),
        ),
        NavigationDecision.navigate,
      );
      await LiveChat.destroy();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
