import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'language_controller.dart';

final feedbackStringsProvider = Provider<FeedbackStrings>((ref) {
  return FeedbackStrings.forLanguage(ref.watch(appLanguageProvider));
});

class FeedbackStrings {
  const FeedbackStrings({
    required this.entryTitle,
    required this.beta,
    required this.heading,
    required this.description,
    required this.categoryLabel,
    required this.bug,
    required this.suggestion,
    required this.other,
    required this.categoryRequired,
    required this.messageLabel,
    required this.messageHint,
    required this.messageRequired,
    required this.messageTooShort,
    required this.send,
    required this.sending,
    required this.thanks,
    required this.backToProfile,
    required this.networkError,
    required this.sessionExpired,
    required this.rateLimited,
    required this.genericError,
  });

  final String entryTitle;
  final String beta;
  final String heading;
  final String description;
  final String categoryLabel;
  final String bug;
  final String suggestion;
  final String other;
  final String categoryRequired;
  final String messageLabel;
  final String messageHint;
  final String messageRequired;
  final String messageTooShort;
  final String send;
  final String sending;
  final String thanks;
  final String backToProfile;
  final String networkError;
  final String sessionExpired;
  final String rateLimited;
  final String genericError;

  static FeedbackStrings forLanguage(AppLanguage language) =>
      switch (language) {
        AppLanguage.english => const FeedbackStrings(
            entryTitle: 'Feedback',
            beta: 'Beta',
            heading: 'Help improve Mushukistan',
            description: 'Mushukistan is still growing. Found a bug or have '
                'an idea? We’d love to hear from you.',
            categoryLabel: 'What kind of feedback is it?',
            bug: 'Bug report',
            suggestion: 'Feature suggestion',
            other: 'Other feedback',
            categoryRequired: 'Choose a category.',
            messageLabel: 'Your message',
            messageHint: 'Tell us what happened or what you would like to see.',
            messageRequired: 'Please write a message.',
            messageTooShort: 'Please write at least 10 characters.',
            send: 'Send feedback',
            sending: 'Sending…',
            thanks: 'Thank you! Your feedback helps us improve Mushukistan.',
            backToProfile: 'Back to Profile',
            networkError:
                'Could not reach Mushukistan. Check your connection and try '
                'again. Your message is still here.',
            sessionExpired: 'Your session has expired. Sign in again to send '
                'feedback.',
            rateLimited: 'You have sent several messages recently. Please '
                'try again a little later.',
            genericError: 'Could not send your feedback. Please try again. '
                'Your message is still here.',
          ),
        AppLanguage.uzbek => const FeedbackStrings(
            entryTitle: 'Fikr-mulohaza',
            beta: 'Beta',
            heading: 'Mushukistanni birga yaxshilaymiz',
            description:
                'Mushukistan hali rivojlanmoqda. Xato topdingizmi yoki '
                'g‘oyangiz bormi? Fikringizni bilishdan xursand bo‘lamiz.',
            categoryLabel: 'Bu qanday fikr-mulohaza?',
            bug: 'Xato haqida xabar',
            suggestion: 'Yangi imkoniyat taklifi',
            other: 'Boshqa fikr',
            categoryRequired: 'Turini tanlang.',
            messageLabel: 'Xabaringiz',
            messageHint:
                'Nima bo‘lganini yoki nimani ko‘rishni xohlashingizni yozing.',
            messageRequired: 'Iltimos, xabar yozing.',
            messageTooShort: 'Kamida 10 ta belgi yozing.',
            send: 'Yuborish',
            sending: 'Yuborilmoqda…',
            thanks: 'Rahmat! Fikringiz Mushukistanni yaxshilashga yordam '
                'beradi.',
            backToProfile: 'Profilga qaytish',
            networkError:
                'Mushukistan bilan aloqa o‘rnatib bo‘lmadi. Internetni '
                'tekshirib, qayta urinib ko‘ring. Xabaringiz saqlanib turibdi.',
            sessionExpired:
                'Seansingiz tugadi. Fikr yuborish uchun qayta kiring.',
            rateLimited: 'Yaqinda bir nechta xabar yubordingiz. Birozdan '
                'keyin qayta urinib ko‘ring.',
            genericError: 'Fikringizni yuborib bo‘lmadi. Qayta urinib '
                'ko‘ring. Xabaringiz saqlanib turibdi.',
          ),
        AppLanguage.russian => const FeedbackStrings(
            entryTitle: 'Обратная связь',
            beta: 'Beta',
            heading: 'Помогите улучшить Mushukistan',
            description: 'Mushukistan ещё развивается. Нашли ошибку или '
                'есть идея? Мы будем рады узнать ваше мнение.',
            categoryLabel: 'О чём вы хотите рассказать?',
            bug: 'Сообщить об ошибке',
            suggestion: 'Предложить функцию',
            other: 'Другое',
            categoryRequired: 'Выберите тип обращения.',
            messageLabel: 'Ваше сообщение',
            messageHint: 'Расскажите, что произошло или что бы вы хотели '
                'увидеть.',
            messageRequired: 'Напишите сообщение.',
            messageTooShort: 'Напишите не менее 10 символов.',
            send: 'Отправить',
            sending: 'Отправляем…',
            thanks: 'Спасибо! Ваш отзыв помогает улучшить Mushukistan.',
            backToProfile: 'Вернуться в профиль',
            networkError: 'Не удалось связаться с Mushukistan. Проверьте '
                'подключение и попробуйте снова. Ваше сообщение сохранено.',
            sessionExpired: 'Сеанс истёк. Войдите снова, чтобы отправить '
                'отзыв.',
            rateLimited: 'Вы недавно отправили несколько сообщений. '
                'Попробуйте чуть позже.',
            genericError: 'Не удалось отправить отзыв. Попробуйте снова. '
                'Ваше сообщение сохранено.',
          ),
      };
}
