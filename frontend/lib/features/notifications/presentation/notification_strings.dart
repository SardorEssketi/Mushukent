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
      'point': 'Alert point',
      'choose_point': 'Choose a point on the map',
      'use_location': 'Use my current location once',
      'save_point': 'Save alert point',
      'disable_nearby': 'Disable and remove saved alert point',
      'nearby_hint':
          'Alerts for new Lost Pets within 500 m of your saved point. Your point is private.',
      'inactivity_hint':
          'One reminder after seven full days away. Returning resets the cycle.',
      'push_unavailable':
          'Android push is not configured or allowed. The in-app inbox still works.',
      'permission_context':
          'Allow Android notifications to receive these alerts on this device?',
      'allow': 'Continue',
      'cancel': 'Cancel',
      'saved': 'Notification settings saved',
      'save_failed': 'Could not save notification settings',
      'location_failed': 'Could not find your current location',
      'select_point': 'Select a point first',
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
      'point': 'Точка оповещений',
      'choose_point': 'Выберите точку на карте',
      'use_location': 'Однократно использовать моё местоположение',
      'save_point': 'Сохранить точку',
      'disable_nearby': 'Отключить и удалить точку оповещений',
      'nearby_hint':
          'Новые объявления о пропавших питомцах в радиусе 500 м. Ваша точка приватна.',
      'inactivity_hint':
          'Одно напоминание через семь полных дней. После возвращения отсчёт начнётся заново.',
      'push_unavailable':
          'Android-уведомления не настроены или запрещены. Уведомления в приложении работают.',
      'permission_context':
          'Разрешить уведомления Android для получения оповещений на этом устройстве?',
      'allow': 'Продолжить',
      'cancel': 'Отмена',
      'saved': 'Настройки уведомлений сохранены',
      'save_failed': 'Не удалось сохранить настройки уведомлений',
      'location_failed': 'Не удалось определить местоположение',
      'select_point': 'Сначала выберите точку',
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
      'point': 'Ogohlantirish nuqtasi',
      'choose_point': 'Xaritadan nuqta tanlang',
      'use_location': 'Joylashuvimdan bir marta foydalanish',
      'save_point': 'Nuqtani saqlash',
      'disable_nearby': 'O‘chirib, saqlangan nuqtani olib tashlash',
      'nearby_hint':
          'Saqlangan nuqtadan 500 m ichidagi yangi yo‘qolgan jonivorlar. Nuqta maxfiy.',
      'inactivity_hint':
          'Yetti to‘liq kundan keyin bir eslatma. Qaytgach davr yangilanadi.',
      'push_unavailable':
          'Android bildirishnomalari sozlanmagan yoki ruxsat berilmagan. Ilova ichidagi xabarlar ishlaydi.',
      'permission_context':
          'Ushbu qurilmada ogohlantirishlar uchun Android bildirishnomalariga ruxsat berasizmi?',
      'allow': 'Davom etish',
      'cancel': 'Bekor qilish',
      'saved': 'Bildirishnoma sozlamalari saqlandi',
      'save_failed': 'Bildirishnoma sozlamalarini saqlab bo‘lmadi',
      'location_failed': 'Joylashuvni aniqlab bo‘lmadi',
      'select_point': 'Avval nuqta tanlang',
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
