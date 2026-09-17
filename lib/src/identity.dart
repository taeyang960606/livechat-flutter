import 'dart:convert';

/// Serializes identity changes so a persisted reset always precedes identify.
/// No webview or Flutter dependency: used by the session and tested in isolation.
class ChatIdentity {
  ChatIdentity({
    required this.readPending,
    required this.writePending,
    required this.evaluate,
  });
  final Future<bool> Function() readPending;
  final Future<void> Function(bool) writePending;
  final Future<void> Function(String) evaluate;
  Map<String, Object>? _customer;
  Map<String, String> _attributes = {};
  bool ready = false;
  Future<void> _tail = Future<void>.value();

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }

  Future<void> identify({
    required String externalId,
    String? name,
    String? email,
    Map<String, String> customParams = const {},
  }) {
    if (externalId.trim().isEmpty) {
      throw ArgumentError('externalId must not be empty');
    }
    final customer = <String, Object>{
      'externalId': externalId,
      'name': ?name,
      'email': ?email,
    };
    final attributes = Map<String, String>.of(customParams);
    return _enqueue(() async {
      _customer = customer;
      _attributes = attributes;
      if (ready) await _apply();
    });
  }

  Future<void> signOut() => _enqueue(() async {
    _customer = null;
    _attributes = {};
    await writePending(true);
    if (ready) await _apply();
  });

  Future<void> onReady() => _enqueue(() async {
    ready = true;
    await _apply();
  });

  Future<void> _apply() async {
    if (await readPending()) {
      await evaluate("window.__livechatCall('reset', []);");
      await writePending(false);
    }
    final customer = _customer;
    if (customer != null) {
      await evaluate(
        "window.__livechatCall('identify', [${jsonEncode(customer)}]);",
      );
      if (_attributes.isNotEmpty) {
        await evaluate(
          "window.__livechatCall('setAttributes', [${jsonEncode(_attributes)}]);",
        );
      }
    }
  }
}
