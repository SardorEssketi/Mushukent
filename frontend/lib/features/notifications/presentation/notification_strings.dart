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
      'settings': 'Notification settings',
      'empty': 'No notifications yet',
      'error': 'Could not load notifications',
      'mark_all': 'Mark all as read',
      'load_more': 'Load more',
      'comment': 'commented on your post',
      'reply': 'replied to your comment',
      'nearby_lost_pet': 'A lost pet was reported near your alert point',
      'deleted_actor': 'Someone',
      'unavailable': 'This content is no longer available.',
      'push_comments': 'Comments on my posts',
      'push_replies': 'Replies to my comments',
      'push_followups': 'Pet follow-up reminders',
      'nearby': 'Nearby Lost Pets',
      'inactivity': 'Inactivity reminders',
      'use_location': 'Use my current location once',
      'save_point': 'Save alert point',
      'nearby_hint':
          'Alerts for new Lost Pets within 500 m of your saved point. Your point is private.',
      'inactivity_hint':
          'One reminder after seven full days away. Returning resets the cycle.',
      'permission_context':
          'Allow Android notifications to receive these alerts on this device?',
      'allow': 'Continue',
      'cancel': 'Cancel',
      'save_failed': 'Could not save notification settings',
      'location_failed': 'Could not find your current location',
      'select_point': 'Select a point first',
      'activity_section': 'Activity',
      'pets_section': 'Pets',
      'nearby_section': 'Nearby',
      'web_status': 'In-app notifications on this browser',
      'web_status_hint':
          'This browser has the Notification Center. Push choices are saved for your Android devices; browser push is not available.',
      'push_not_configured': 'Device push is unavailable',
      'push_not_configured_hint':
          'Your preferences are saved, and the in-app Notification Center still works. Push is not configured for this app or server.',
      'push_enabled': 'Android notifications are on',
      'push_enabled_hint':
          'This device can receive push alerts for the categories you choose below.',
      'device_push_disabled': 'Notifications are off on this device',
      'device_push_disabled_hint':
          'Your preferences are saved, but Android cannot show push alerts yet. The in-app Notification Center still works.',
      'enable_notifications': 'Enable notifications',
      'open_android_settings': 'Open Android settings',
      'choose_map': 'Choose on map',
      'change_point': 'Change alert point',
      'enable_nearby': 'Save point and turn on alerts',
      'map_guidance': 'Tap the map to choose your private alert point.',
      'retry': 'Try again',
      'permission_failed': 'Could not enable notifications on this device',
      'settings_failed': 'Could not open Android settings',
    },
    'ru': {
      'title': 'Уведомления',
      'settings': 'Настройки уведомлений',
      'empty': 'Пока нет уведомлений',
      'error': 'Не удалось загрузить уведомления',
      'mark_all': 'Отметить все как прочитанные',
      'load_more': 'Загрузить ещё',
      'comment': 'прокомментировал(а) вашу публикацию',
      'reply': 'ответил(а) на ваш комментарий',
      'nearby_lost_pet': 'Рядом с выбранной точкой ищут питомца',
      'deleted_actor': 'Пользователь',
      'unavailable': 'Этот материал больше недоступен.',
      'push_comments': 'Комментарии к моим публикациям',
      'push_replies': 'Ответы на мои комментарии',
      'push_followups': 'Напоминания о питомцах',
      'nearby': 'Пропавшие питомцы рядом',
      'inactivity': 'Напоминания о возвращении',
      'use_location': 'Однократно использовать моё местоположение',
      'save_point': 'Сохранить точку',
      'nearby_hint':
          'Новые объявления о пропавших питомцах в радиусе 500 м. Ваша точка приватна.',
      'inactivity_hint':
          'Одно напоминание через семь полных дней. После возвращения отсчёт начнётся заново.',
      'permission_context':
          'Разрешить уведомления Android для получения оповещений на этом устройстве?',
      'allow': 'Продолжить',
      'cancel': 'Отмена',
      'save_failed': 'Не удалось сохранить настройки уведомлений',
      'location_failed': 'Не удалось определить местоположение',
      'select_point': 'Сначала выберите точку',
      'activity_section': 'Активность',
      'pets_section': 'Питомцы',
      'nearby_section': 'Рядом',
      'web_status': 'Уведомления внутри приложения',
      'web_status_hint':
          'В браузере работает центр уведомлений. Настройки push сохраняются для ваших устройств Android; push в браузере нет.',
      'push_not_configured': 'Push на устройстве недоступен',
      'push_not_configured_hint':
          'Ваши настройки сохранены, а центр уведомлений работает. Push не настроен в приложении или на сервере.',
      'push_enabled': 'Уведомления Android включены',
      'push_enabled_hint':
          'Это устройство может получать push для выбранных ниже категорий.',
      'device_push_disabled': 'Уведомления на устройстве выключены',
      'device_push_disabled_hint':
          'Ваши настройки сохранены, но Android пока не может показывать push. Уведомления внутри приложения работают.',
      'enable_notifications': 'Включить уведомления',
      'open_android_settings': 'Открыть настройки Android',
      'choose_map': 'Выбрать на карте',
      'change_point': 'Изменить точку оповещений',
      'enable_nearby': 'Сохранить точку и включить оповещения',
      'map_guidance':
          'Нажмите на карту, чтобы выбрать приватную точку оповещений.',
      'retry': 'Повторить',
      'permission_failed': 'Не удалось включить уведомления на устройстве',
      'settings_failed': 'Не удалось открыть настройки Android',
    },
    'uz': {
      'title': 'Bildirishnomalar',
      'settings': 'Bildirishnoma sozlamalari',
      'empty': 'Hozircha bildirishnomalar yo‘q',
      'error': 'Bildirishnomalarni yuklab bo‘lmadi',
      'mark_all': 'Barchasini o‘qilgan deb belgilash',
      'load_more': 'Yana yuklash',
      'comment': 'postingizga izoh qoldirdi',
      'reply': 'izohingizga javob berdi',
      'nearby_lost_pet':
          'Tanlangan joy yaqinida jonivor yo‘qolgani e’lon qilindi',
      'deleted_actor': 'Foydalanuvchi',
      'unavailable': 'Bu kontent endi mavjud emas.',
      'push_comments': 'Postlarimga izohlar',
      'push_replies': 'Izohlarimga javoblar',
      'push_followups': 'Jonivor bo‘yicha eslatmalar',
      'nearby': 'Yaqindagi yo‘qolgan jonivorlar',
      'inactivity': 'Qaytish eslatmalari',
      'use_location': 'Joylashuvimdan bir marta foydalanish',
      'save_point': 'Nuqtani saqlash',
      'nearby_hint':
          'Saqlangan nuqtadan 500 m ichidagi yangi yo‘qolgan jonivorlar. Nuqta maxfiy.',
      'inactivity_hint':
          'Yetti to‘liq kundan keyin bir eslatma. Qaytgach davr yangilanadi.',
      'permission_context':
          'Ushbu qurilmada ogohlantirishlar uchun Android bildirishnomalariga ruxsat berasizmi?',
      'allow': 'Davom etish',
      'cancel': 'Bekor qilish',
      'save_failed': 'Bildirishnoma sozlamalarini saqlab bo‘lmadi',
      'location_failed': 'Joylashuvni aniqlab bo‘lmadi',
      'select_point': 'Avval nuqta tanlang',
      'activity_section': 'Faollik',
      'pets_section': 'Jonivorlar',
      'nearby_section': 'Yaqin atrof',
      'web_status': 'Ilova ichidagi bildirishnomalar',
      'web_status_hint':
          'Brauzerda Bildirishnomalar markazi ishlaydi. Push tanlovlari Android qurilmalaringiz uchun saqlanadi; brauzer push xabarlari mavjud emas.',
      'push_not_configured': 'Qurilmada push mavjud emas',
      'push_not_configured_hint':
          'Tanlovlaringiz saqlandi, ilova ichidagi bildirishnomalar ishlaydi. Push ilova yoki serverda sozlanmagan.',
      'push_enabled': 'Android bildirishnomalari yoqilgan',
      'push_enabled_hint':
          'Bu qurilma quyida tanlangan turdagi push xabarlarni olishi mumkin.',
      'device_push_disabled': 'Qurilmada bildirishnomalar o‘chiq',
      'device_push_disabled_hint':
          'Tanlovlaringiz saqlandi, lekin Android hozircha push xabarlarni ko‘rsata olmaydi. Ilova ichidagi bildirishnomalar ishlaydi.',
      'enable_notifications': 'Bildirishnomalarni yoqish',
      'open_android_settings': 'Android sozlamalarini ochish',
      'choose_map': 'Xaritadan tanlash',
      'change_point': 'Ogohlantirish nuqtasini o‘zgartirish',
      'enable_nearby': 'Nuqtani saqlash va ogohlantirishlarni yoqish',
      'map_guidance':
          'Maxfiy ogohlantirish nuqtasini tanlash uchun xaritaga teging.',
      'retry': 'Qayta urinish',
      'permission_failed': 'Qurilmada bildirishnomalarni yoqib bo‘lmadi',
      'settings_failed': 'Android sozlamalarini ochib bo‘lmadi',
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
