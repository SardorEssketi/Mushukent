import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../auth/application/auth_controller.dart';
import '../data/notification_api.dart';
import '../presentation/notification_center_screen.dart';
import '../presentation/nearby_alert_privacy.dart';
import '../presentation/notification_strings.dart';
import 'nearby_alerts.dart';

class AndroidPushConfiguration {
  static const enabled = bool.fromEnvironment('ENABLE_ANDROID_PUSH');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> initialize() async {
    if (!supported || !enabled) return;
    // Android's native default app is configured by google-services.json.
    await Firebase.initializeApp();
  }

  static bool get ready => supported && enabled && Firebase.apps.isNotEmpty;
}

enum DevicePushPermission {
  web,
  unavailable,
  notDetermined,
  denied,
  deniedPermanently,
  allowed,
}

final devicePushAccessProvider = Provider<DevicePushAccess>((ref) {
  return DevicePushAccess();
});

class DevicePushAccess {
  static const _settingsChannel =
      MethodChannel('mushukistan/notification_settings');

  bool get available => AndroidPushConfiguration.ready;

  // Android 13+ reports denied both before the first prompt and after denial.
  // A local one-time disclosure marker prevents repeated requests.
  static bool shouldExplainPermission(DevicePushPermission status,
          {required bool alreadyAsked}) =>
      !alreadyAsked &&
      (status == DevicePushPermission.notDetermined ||
          status == DevicePushPermission.denied);

  Future<DevicePushPermission> status() async {
    if (!AndroidPushConfiguration.supported) return DevicePushPermission.web;
    if (!AndroidPushConfiguration.ready) {
      final status = await _settingsChannel
          .invokeMethod<String>('notificationPermissionStatus');
      return status == 'allowed'
          ? DevicePushPermission.allowed
          : DevicePushPermission.denied;
    }
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional =>
        DevicePushPermission.allowed,
      AuthorizationStatus.notDetermined => DevicePushPermission.notDetermined,
      AuthorizationStatus.deniedPermanently =>
        DevicePushPermission.deniedPermanently,
      AuthorizationStatus.denied => DevicePushPermission.denied,
    };
  }

  Future<bool> requestPermission() => AndroidPushService.requestPermission();

  Future<void> openSettings() async {
    if (!AndroidPushConfiguration.supported) return;
    await _settingsChannel.invokeMethod<void>('openNotificationSettings');
  }
}

class AndroidPushService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'registered_android_push_token';
  static const _userKey = 'registered_android_push_user';

  static Future<bool> authorized() async {
    if (!AndroidPushConfiguration.ready) return false;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  static Future<bool> requestPermission() async {
    if (!AndroidPushConfiguration.ready) return false;
    final settings = await FirebaseMessaging.instance.requestPermission();
    final allowed =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
    if (allowed) await FirebaseMessaging.instance.setAutoInitEnabled(true);
    return allowed;
  }

  static Future<String?> token() async {
    if (!await authorized()) return null;
    await retryPendingRevocation();
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    return FirebaseMessaging.instance.getToken();
  }

  static Future<void> retryPendingRevocation() async {
    if (!AndroidPushConfiguration.ready ||
        await _storage.read(key: _userKey) != null ||
        await _storage.read(key: _tokenKey) == null) {
      return;
    }
    await FirebaseMessaging.instance.setAutoInitEnabled(false);
    await FirebaseMessaging.instance.deleteToken();
    await _storage.delete(key: _tokenKey);
  }

  static Future<String?> tokenForLogout() async {
    if (!AndroidPushConfiguration.supported) return null;
    return _storage.read(key: _tokenKey);
  }

  static Future<void> register(
      NotificationApi api, String userId, String token) async {
    final priorUser = await _storage.read(key: _userKey);
    final priorToken = await _storage.read(key: _tokenKey);
    await api.registerToken(
      token,
      previousToken:
          priorUser == userId && priorToken != token ? priorToken : null,
    );
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userKey, value: userId);
  }

  static Future<void> clearRegisteredToken() async {
    if (!AndroidPushConfiguration.supported) return;
    try {
      if (AndroidPushConfiguration.ready) {
        await FirebaseMessaging.instance.setAutoInitEnabled(false);
        await FirebaseMessaging.instance.deleteToken();
        await _storage.delete(key: _tokenKey);
      }
    } finally {
      // Keep the token if native revocation failed so a later launch can retry.
      await _storage.delete(key: _userKey);
    }
  }

  static Future<void> revokeIfPermissionDenied(NotificationApi api) async {
    if (!AndroidPushConfiguration.ready || await authorized()) return;
    final token = await _storage.read(key: _tokenKey);
    if (token == null) return;
    try {
      await api.unregisterToken(token);
    } catch (_) {
      // A later FCM invalid-token response also retires the server record.
    }
    await clearRegisteredToken();
  }
}

class NotificationLifecycle extends ConsumerStatefulWidget {
  const NotificationLifecycle(
      {super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<NotificationLifecycle> createState() =>
      _NotificationLifecycleState();
}

class _NotificationLifecycleState extends ConsumerState<NotificationLifecycle>
    with WidgetsBindingObserver {
  String? _activeUser;
  String? _registeredUser;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _openSubscription;
  RemoteMessage? _pendingOpen;
  Timer? _unreadTimer;
  late final NearbyAlerts _nearby;

  @override
  void initState() {
    super.initState();
    _nearby = ref.read(nearbyAlertsProvider);
    final initialLifecycle = WidgetsBinding.instance.lifecycleState;
    _nearby.foreground(initialLifecycle == null ||
        initialLifecycle == AppLifecycleState.resumed);
    WidgetsBinding.instance.addObserver(this);
    unawaited(AndroidPushService.retryPendingRevocation().catchError((_) {}));
    _unreadTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_activeUser != null) ref.invalidate(unreadNotificationCountProvider);
    });
    if (AndroidPushConfiguration.ready) {
      _tokenSubscription =
          FirebaseMessaging.instance.onTokenRefresh.listen((_) {
        if (_activeUser != null) {
          unawaited(_sync(_activeUser!, forceRegistration: true));
        }
      });
      _messageSubscription = FirebaseMessaging.onMessage.listen((_) {
        ref.invalidate(unreadNotificationCountProvider);
      });
      _openSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen(_handlePush);
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null && mounted) _handlePush(message);
      });
    }
  }

  void _handlePush(RemoteMessage message) {
    if (!mounted) return;
    final phase = ref.read(authControllerProvider).phase;
    if (phase == AuthPhase.initial || phase == AuthPhase.restoring) {
      _pendingOpen = message;
      return;
    }
    _openPush(message);
  }

  void _openPush(RemoteMessage message) {
    if (!mounted) return;
    final notificationId = message.data['notification_id'];
    if (notificationId != null &&
        RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(notificationId) &&
        ref.read(authControllerProvider).isAuthenticated) {
      unawaited(ref
          .read(notificationApiProvider)
          .markRead(notificationId)
          .then((_) => ref.invalidate(unreadNotificationCountProvider))
          .catchError((_) {}));
    }
    if (message.data['kind'] == 'lost_pet_followup' ||
        message.data['kind'] == 'adoption_followup') {
      // The existing feed shell checks the persisted due follow-ups on entry.
      final auth = ref.read(authControllerProvider);
      // An unconfirmed (server unreachable) session is still a signed-in user: never send
      // them to the sign-in page.
      widget.router.go(
        auth.isAuthenticated || auth.hasUnconfirmedSession ? '/feed' : '/login',
      );
      return;
    }
    if (message.data['kind'] == 'inactivity') {
      widget.router.go('/feed');
      return;
    }
    final kind = message.data['target_kind'];
    final id = message.data['target_id'];
    final path =
        kind == null || id == null ? null : notificationTargetPath(kind, id);
    final destination = path != null &&
            (message.data['kind'] == 'comment' ||
                message.data['kind'] == 'reply')
        ? '$path?comments=1'
        : path;
    openNotificationDestination(widget.router, destination ?? '/notifications');
  }

  Future<void> _sync(String userId, {bool forceRegistration = false}) async {
    try {
      await ref.read(notificationApiProvider).recordActivity();
    } catch (_) {
      // Activity reporting is advisory; do not block the app.
    }
    if (!forceRegistration && mounted && _activeUser == userId) {
      await _nearby.sync(userId, disclose: () async {
        final dialogContext =
            widget.router.routerDelegate.navigatorKey.currentContext;
        if (dialogContext == null || !mounted || _activeUser != userId) {
          return false;
        }
        return await discloseNearbyAlerts(
                dialogContext, ref.read(notificationStringsProvider)) ??
            false;
      });
    }
    if (!mounted || _activeUser != userId) return;
    if (!AndroidPushConfiguration.ready) {
      return;
    }
    try {
      final access = ref.read(devicePushAccessProvider);
      if (DevicePushAccess.shouldExplainPermission(await access.status(),
          alreadyAsked:
              await ref.read(nearbyConsentStoreProvider).pushAsked(userId))) {
        final dialogContext =
            widget.router.routerDelegate.navigatorKey.currentContext;
        if (dialogContext == null || !mounted || _activeUser != userId) return;
        await ref.read(nearbyConsentStoreProvider).markPushAsked(userId);
        if (!dialogContext.mounted || !mounted || _activeUser != userId) return;
        final copy = ref.read(notificationStringsProvider);
        final allowed = await showDialog<bool>(
            context: dialogContext,
            builder: (context) => AlertDialog(
                  content: Text(copy.get('permission_context')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(copy.get('cancel'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(copy.get('allow'))),
                  ],
                ));
        if (!mounted || _activeUser != userId) return;
        if (allowed == true) await access.requestPermission();
      }
      if (!await AndroidPushService.authorized()) {
        await AndroidPushService.revokeIfPermissionDenied(
          ref.read(notificationApiProvider),
        );
        _registeredUser = null;
        return;
      }
      if (_registeredUser == userId && !forceRegistration) return;
      final token = await AndroidPushService.token();
      if (token != null && mounted && _activeUser == userId) {
        await AndroidPushService.register(
          ref.read(notificationApiProvider),
          userId,
          token,
        );
        _registeredUser = userId;
      }
    } catch (_) {
      // Token registration can retry on the next authenticated resume.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _nearby.foreground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed && _activeUser != null) {
      unawaited(_sync(_activeUser!));
      ref.invalidate(unreadNotificationCountProvider);
    } else if (state == AppLifecycleState.paused && _activeUser != null) {
      // Record the end of a long foreground session when possible.
      unawaited(ref
          .read(notificationApiProvider)
          .recordActivity()
          .catchError((_) {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase =
        ref.watch(authControllerProvider.select((state) => state.phase));
    if (_pendingOpen != null &&
        phase != AuthPhase.initial &&
        phase != AuthPhase.restoring) {
      final pending = _pendingOpen!;
      _pendingOpen = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _handlePush(pending));
    }
    final user = ref.watch(currentUserProvider);
    if (_activeUser != user?.id) {
      _activeUser = user?.id;
      _nearby.activate(_activeUser);
      _registeredUser = null;
      if (_activeUser != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _activeUser != null) unawaited(_sync(_activeUser!));
        });
      }
    }
    return widget.child;
  }

  @override
  void dispose() {
    _nearby.activate(null);
    WidgetsBinding.instance.removeObserver(this);
    _tokenSubscription?.cancel();
    _messageSubscription?.cancel();
    _openSubscription?.cancel();
    _unreadTimer?.cancel();
    super.dispose();
  }
}
