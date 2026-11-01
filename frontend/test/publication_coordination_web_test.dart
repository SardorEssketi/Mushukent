@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/publication_retry.dart';
import 'package:mushukistan_frontend/core/network/publication_session.dart';
import 'package:mushukistan_frontend/core/storage/token_store.dart';
import 'package:mushukistan_frontend/core/storage/token_store_factory_web.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:web/web.dart' as web;

import 'core/network/publication_retry_test.dart' as support;

@JS('Object.defineProperty')
external JSObject defineProperty(
    JSObject object, String key, JSObject descriptor);
@JS('Reflect.deleteProperty')
external bool deleteProperty(JSObject object, String key);

void main() {
  test('external browser account transition invalidates publication session',
      () async {
    final store = GuardedAuthTokenStore(WebLocalTokenStore());
    await store.write('header.eyJzdWIiOiJBIn0.signature');
    final binding = PublicationSession(store);
    await binding.credentials();
    final changed = Completer<void>();
    final changes = store.sessionChanges.listen((_) {
      if (!changed.isCompleted) changed.complete();
    });
    try {
      web.window.localStorage.setItem(
          'mushukistan_access_token', 'header.eyJzdWIiOiJCIn0.signature');
      web.window.dispatchEvent(web.StorageEvent(
          'storage',
          web.StorageEventInit(
              key: 'mushukistan_access_token',
              oldValue: 'header.eyJzdWIiOiJBIn0.signature',
              newValue: 'header.eyJzdWIiOiJCIn0.signature')));
      await changed.future.timeout(const Duration(seconds: 3));
      expect(binding.cancelToken.isCancelled, isTrue);
      await expectLater(
          binding.credentials(),
          throwsA(isA<MushukistanApiException>()
              .having((e) => e.code, 'code', 'SESSION_CHANGED')));
    } finally {
      await changes.cancel();
      await binding.dispose();
      await store.delete();
      await store.dispose();
    }
  });
  test('exclusive publication lock spans another same-origin browsing context',
      () async {
    final id = newPublicationKey();
    SharedPreferencesPlugin.registerWith(null);
    final cached = await SharedPreferences.getInstance();
    final storageKey = 'flutter.publication_attempt_v2.$id';
    expect(cached.getString('publication_attempt_v2.$id'), isNull);
    const record =
        PublicationRecord('synthetic-owner-hash', 'synthetic-fingerprint');
    final held = Completer<void>();
    final listener = ((web.MessageEvent event) {
      if (event.data.dartify() == id && !held.isCompleted) held.complete();
    }).toJS;
    web.window.addEventListener('message', listener);
    final frame = web.HTMLIFrameElement()
      ..srcdoc = '''<script>
        navigator.locks.request('mushukistan-publication-v2:$id', async () => {
          localStorage.setItem('$storageKey', JSON.stringify(${jsonEncode(record.encode())}));
          const release = new Promise(resolve => window.addEventListener('message', resolve, {once:true}));
          parent.postMessage('$id', '*');
          await release;
        });
      </script>'''
          .toJS;
    web.document.body!.appendChild(frame);
    try {
      await held.future.timeout(const Duration(seconds: 5));
      bool entered = false;
      final journal = PreferencesPublicationJournal();
      final attempt = journal.coordinate(id, () async {
        entered = true;
        return journal.read(id);
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(entered, isFalse);
      frame.contentWindow!.postMessage('release'.toJS, '*'.toJS);
      final restored = await attempt.timeout(const Duration(seconds: 5));
      expect(restored?.owner, record.owner);
      expect(restored?.fingerprint, record.fingerprint);
      expect(entered, isTrue);
    } finally {
      frame.remove();
      web.window.localStorage.removeItem(storageKey);
      web.window.removeEventListener('message', listener);
    }
  });

  test('missing Web Locks blocks publication before any network request',
      () async {
    final navigator = web.window.navigator;
    defineProperty(navigator, 'locks',
        {'configurable': true, 'value': null}.jsify() as JSObject);
    try {
      final server = support.Server()..failFirst = false;
      final api = await support.client(server, MemoryPublicationJournal());
      await expectLater(
          support.publish(api),
          throwsA(isA<MushukistanApiException>().having(
              (e) => e.code, 'code', 'PUBLICATION_COORDINATION_UNAVAILABLE')));
      expect(server.requests, isEmpty);
    } finally {
      deleteProperty(navigator, 'locks');
    }
  });
}
