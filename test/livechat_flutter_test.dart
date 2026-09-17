import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:livechat_flutter/livechat_flutter.dart';
import 'package:livechat_flutter/src/identity.dart';

void main() {
  test('URL mirrors Android with trailing slash and merchant whitespace', () {
    expect(
      chatUrlOf('https://chat.example.test///', '  01JMERCHANT\n').toString(),
      'https://chat.example.test/widget/app/01JMERCHANT',
    );
    expect(
      chatUrlOf('http://localhost:8080/chat/', 'merchant-1').toString(),
      'http://localhost:8080/chat/widget/app/merchant-1',
    );
  });
  test('rejects invalid or ambiguous deployment URLs and merchant IDs', () {
    for (final url in [
      'javascript:alert(1)',
      'file:///tmp/chat',
      'https://',
      'https://chat.test/?tenant=1',
      'https://user:pass@chat.test',
    ]) {
      expect(() => chatUrlOf(url, 'merchant'), throwsArgumentError);
    }
    for (final id in ['', '  ', '../other', 'id?x=1']) {
      expect(() => chatUrlOf('https://chat.test', id), throwsArgumentError);
    }
  });
  test('message parsing tolerates optional fields and numeric IDs', () {
    final message = ChatMessage.fromJson({
      'id': '42',
      'body': 'Hello',
      'senderType': 'operator',
      'senderName': '',
      'hasAttachment': true,
    });
    expect(message.id, 42);
    expect(message.senderName, isNull);
    expect(message.hasAttachment, isTrue);
    expect(ChatMessage.fromJson({}).body, '');
  });

  group('identity ordering', () {
    late bool pending;
    late List<String> calls;
    late ChatIdentity identity;
    setUp(() {
      pending = false;
      calls = [];
      identity = ChatIdentity(
        readPending: () async => pending,
        writePending: (value) async {
          pending = value;
        },
        evaluate: (script) async {
          calls.add(script);
        },
      );
    });
    test(
      'sign-out persists before startup and resets before next member',
      () async {
        await identity.signOut();
        expect(pending, isTrue);
        expect(calls, isEmpty);
        await identity.identify(
          externalId: 'new-member',
          customParams: {'plan': 'vip'},
        );
        await identity.onReady();
        expect(calls.map((s) => s.split("'")[1]), [
          'reset',
          'identify',
          'setAttributes',
        ]);
        expect(pending, isFalse);
      },
    );
    test(
      'a fresh instance replays the saved sign-out after process restart',
      () async {
        await identity.signOut();
        final restarted = ChatIdentity(
          readPending: () async => pending,
          writePending: (value) async {
            pending = value;
          },
          evaluate: (script) async {
            calls.add(script);
          },
        );
        await restarted.onReady();
        expect(calls.single, contains("'reset'"));
        expect(pending, isFalse);
      },
    );
    test('failed reset remains pending and can be retried', () async {
      pending = true;
      var fail = true;
      final broken = ChatIdentity(
        readPending: () async => pending,
        writePending: (value) async {
          pending = value;
        },
        evaluate: (script) async {
          if (fail) throw StateError('page gone');
          calls.add(script);
        },
      );
      await expectLater(broken.onReady(), throwsStateError);
      expect(pending, isTrue);
      fail = false;
      await broken.onReady();
      expect(pending, isFalse);
    });
    test(
      'overlapping calls cannot identify a new member before reset finishes',
      () async {
        final gate = Completer<void>();
        final serial = ChatIdentity(
          readPending: () async => pending,
          writePending: (value) async {
            pending = value;
          },
          evaluate: (script) async {
            calls.add(script);
            if (script.contains("'reset'")) await gate.future;
          },
        );
        await serial.onReady();
        final reset = serial.signOut();
        final identify = serial.identify(externalId: 'next');
        await Future<void>.delayed(Duration.zero);
        expect(calls.length, 1);
        expect(calls.single, contains("'reset'"));
        gate.complete();
        await Future.wait([reset, identify]);
        expect(calls.last, contains("'identify'"));
      },
    );
    test(
      'identity data is encoded as JSON rather than interpolated JS',
      () async {
        const hostile = "member'); window.evil = true; //\n\"";
        await identity.identify(externalId: hostile);
        await identity.onReady();
        expect(calls.single, contains(jsonEncode(hostile)));
      },
    );
    test(
      'sign-out removes the remembered customer on future page loads',
      () async {
        await identity.identify(externalId: 'old');
        await identity.onReady();
        await identity.signOut();
        calls.clear();
        identity.ready = false;
        await identity.onReady();
        expect(calls, isEmpty);
      },
    );
  });
}
