import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/language_controller.dart';
import '../data/notification_api.dart';

final notificationStringsProvider = Provider<NotificationStrings>((ref) {
  return NotificationStrings(ref.watch(appLanguageProvider).code);
});

class NotificationStrings {
  const NotificationStrings(this.language);
  final String language;

  static const _copy = <String, Map<String, String>>{
    'en': {
      'title': 'Notifications',
      'empty': 'No notifications yet',
      'error': 'Could not load notifications',
      'mark_all': 'Mark all as read',
      'load_more': 'Load more',
      'comment': 'commented on your post',
      'reply': 'replied to your comment',
      'deleted_actor': 'Someone',
      'unavailable': 'This content is no longer available.',
      'permission_context':
          'Allow Android notifications to receive these alerts on this device?',
      'allow': 'Continue',
      'cancel': 'Cancel',
      'open_android_settings': 'Open Android settings',
      'retry': 'Try again',
      'settings_failed': 'Could not open Android settings',
      'nearby_lost_pet':
          "A lost pet was reported near your last authorized location",
      'automatic_hint':
          "Comments, replies, pet follow-ups and inactivity reminders are enabled automatically.",
      'permission_status': "Android notification permission",
      'permission_allowed': "Allowed",
      'permission_denied': "Not allowed",
      'android_only': "Available in the Android app",
      'push_status': "Push delivery",
      'push_available': "Available on this device",
      'push_unavailable':
          "Unavailable: Android permission and configured push delivery are required.",
      'nearby': "Nearby lost-pet alerts",
      'nearby_available':
          "Available within 500 m of your last authorized location",
      'nearby_permission_missing':
          "Unavailable: location permission and enabled location services are required.",
      'nearby_consent_missing':
          "Unavailable: location privacy consent is required.",
      'nearby_unavailable':
          "Unavailable: a current device location has not been confirmed.",
      'inbox_hint':
          "The Notification Center works even when Android push permission is denied.",
      'location_privacy': "Nearby alert privacy",
      'nearby_disclosure':
          "With your consent and Android location permission, Mushukistan privately stores only your last device location for lost-pet alerts within 500 m. It refreshes on app launch or resume, without background tracking or location history. Withdraw consent under Profile → Settings → Nearby alert privacy; revoking permission also removes the point when the app next connects.",
      'consent_allow': "Allow private nearby alerts",
      'consent_decline': "Do not use my location",
      'open_location_settings': "Open Android location permissions",
      'sync_failed':
          "Could not sync nearby alerts. Changes will retry when the app is active and online.",
    },
    'ru': {
      'title': 'Уведомления',
      'empty': 'Пока нет уведомлений',
      'error': 'Не удалось загрузить уведомления',
      'mark_all': 'Отметить все как прочитанные',
      'load_more': 'Загрузить ещё',
      'comment': 'прокомментировал(а) вашу публикацию',
      'reply': 'ответил(а) на ваш комментарий',
      'deleted_actor': 'Пользователь',
      'unavailable': 'Этот материал больше недоступен.',
      'permission_context':
          'Разрешить уведомления Android для получения оповещений на этом устройстве?',
      'allow': 'Продолжить',
      'cancel': 'Отмена',
      'open_android_settings': 'Открыть настройки Android',
      'retry': 'Повторить',
      'settings_failed': 'Не удалось открыть настройки Android',
      'nearby_lost_pet':
          "Рядом с вашим последним разрешённым местоположением ищут питомца",
      'automatic_hint':
          "Комментарии, ответы, напоминания о питомцах и возвращении включены автоматически.",
      'permission_status': "Разрешение на уведомления Android",
      'permission_allowed': "Разрешено",
      'permission_denied': "Не разрешено",
      'android_only': "Доступно в приложении Android",
      'push_status': "Доставка push",
      'push_available': "Доступна на этом устройстве",
      'push_unavailable':
          "Недоступна: нужны разрешение Android и настроенная доставка push.",
      'nearby': "Пропавшие питомцы рядом",
      'nearby_available':
          "Доступно в радиусе 500 м от последнего разрешённого местоположения",
      'nearby_permission_missing':
          "Недоступно: нужны разрешение на геолокацию и включённые службы местоположения.",
      'nearby_consent_missing':
          "Недоступно: нужно согласие на приватное использование местоположения.",
      'nearby_unavailable':
          "Недоступно: текущее местоположение устройства ещё не подтверждено.",
      'inbox_hint':
          "Центр уведомлений работает, даже если push-уведомления запрещены в Android.",
      'location_privacy': "Приватность геолокации для оповещений",
      'nearby_disclosure':
          "С вашего согласия и при разрешении Android Mushukistan приватно хранит только последнее местоположение устройства для оповещений о пропавших питомцах в радиусе 500 м. Оно обновляется при запуске или возвращении в приложение, без фонового отслеживания и истории перемещений. Отозвать согласие можно в Профиль → Настройки → Приватность геолокации для оповещений. При отзыве разрешения точка удалится, когда приложение снова подключится.",
      'consent_allow': "Разрешить приватные оповещения рядом",
      'consent_decline': "Не использовать моё местоположение",
      'open_location_settings': "Открыть разрешения геолокации Android",
      'sync_failed':
          "Не удалось синхронизировать оповещения рядом. Повторим при активном приложении и подключении к сети.",
    },
    'uz': {
      'title': 'Bildirishnomalar',
      'empty': 'Hozircha bildirishnomalar yo‘q',
      'error': 'Bildirishnomalarni yuklab bo‘lmadi',
      'mark_all': 'Barchasini o‘qilgan deb belgilash',
      'load_more': 'Yana yuklash',
      'comment': 'postingizga izoh qoldirdi',
      'reply': 'izohingizga javob berdi',
      'deleted_actor': 'Foydalanuvchi',
      'unavailable': 'Bu kontent endi mavjud emas.',
      'permission_context':
          'Ushbu qurilmada ogohlantirishlar uchun Android bildirishnomalariga ruxsat berasizmi?',
      'allow': 'Davom etish',
      'cancel': 'Bekor qilish',
      'open_android_settings': 'Android sozlamalarini ochish',
      'retry': 'Qayta urinish',
      'settings_failed': 'Android sozlamalarini ochib bo‘lmadi',
      'nearby_lost_pet':
          "Oxirgi ruxsat berilgan joylashuvingiz yaqinida jonivor yo‘qolgani e’lon qilindi",
      'automatic_hint':
          "Izohlar, javoblar, jonivorlar va qaytish haqidagi eslatmalar avtomatik yoqilgan.",
      'permission_status': "Android bildirishnoma ruxsati",
      'permission_allowed': "Ruxsat berilgan",
      'permission_denied': "Ruxsat berilmagan",
      'android_only': "Android ilovasida mavjud",
      'push_status': "Push xabarlarni yetkazish",
      'push_available': "Ushbu qurilmada mavjud",
      'push_unavailable':
          "Mavjud emas: Android ruxsati va sozlangan push xizmati kerak.",
      'nearby': "Yaqindagi yo‘qolgan jonivorlar",
      'nearby_available':
          "Oxirgi ruxsat berilgan joylashuvdan 500 m ichida mavjud",
      'nearby_permission_missing':
          "Mavjud emas: joylashuv ruxsati va yoqilgan joylashuv xizmatlari kerak.",
      'nearby_consent_missing':
          "Mavjud emas: joylashuvdan maxfiy foydalanishga rozilik kerak.",
      'nearby_unavailable':
          "Mavjud emas: qurilmaning joriy joylashuvi hali tasdiqlanmagan.",
      'inbox_hint':
          "Android push ruxsati rad etilsa ham Bildirishnomalar markazi ishlaydi.",
      'location_privacy': "Yaqin atrof ogohlantirishlari maxfiyligi",
      'nearby_disclosure':
          "Roziligingiz va Android joylashuv ruxsati bilan Mushukistan 500 m ichidagi yo‘qolgan jonivorlar haqida ogohlantirish uchun faqat qurilmangizning oxirgi joylashuvini maxfiy saqlaydi. U ilova ishga tushganda yoki unga qaytganda yangilanadi; fon kuzatuvi va joylashuv tarixi yo‘q. Rozilikni Profil → Sozlamalar → Yaqin atrof ogohlantirishlari maxfiyligi orqali bekor qilishingiz mumkin. Ruxsat bekor qilinsa, ilova keyingi ulanishda nuqtani o‘chiradi.",
      'consent_allow': "Maxfiy yaqin atrof ogohlantirishlariga roziman",
      'consent_decline': "Joylashuvimdan foydalanmang",
      'open_location_settings': "Android joylashuv ruxsatlarini ochish",
      'sync_failed':
          "Yaqin atrof ogohlantirishlarini sinxronlab bo‘lmadi. Ilova faol va tarmoqqa ulanganda qayta uriniladi.",
    },
  };

  String get(String key) => _copy[language]?[key] ?? _copy['en']![key] ?? key;

  String forEntry(NotificationEntry entry) {
    if (entry.kind == 'nearby_lost_pet') return get('nearby_lost_pet');
    final actor = entry.actorName?.trim().isNotEmpty == true
        ? entry.actorName!
        : get('deleted_actor');
    return '$actor ${get(entry.kind)}';
  }
}
