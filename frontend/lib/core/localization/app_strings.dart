import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'language_controller.dart';

final appStringsProvider = Provider<AppStrings>((ref) {
  return AppStrings.forLanguage(ref.watch(appLanguageProvider));
});

class AppStrings {
  const AppStrings({
    required this.welcomeBack,
    required this.signInToMushukistan,
    required this.email,
    required this.emailHint,
    required this.password,
    required this.login,
    required this.continueWithGoogle,
    required this.createAnAccount,
    required this.createAccount,
    required this.joinMushukistan,
    required this.nameOptional,
    required this.register,
    required this.alreadyHaveAccount,
    required this.language,
    required this.emailRequired,
    required this.invalidEmail,
    required this.passwordRequired,
    required this.passwordMin8,
    required this.nameTooLong,
    required this.verifyEmail,
    required this.confirmYourEmail,
    required this.verifyEmailWithoutAddress,
    required this.verifyEmailWithAddress,
    required this.devVerificationHelp,
    required this.verifyNow,
    required this.resendVerification,
    required this.backToLogin,
    required this.sessionCheckFailed,
    required this.retry,
    required this.continueToLogin,
    required this.restoringSession,
    required this.feed,
    required this.map,
    required this.add,
    required this.leaders,
    required this.profile,
    required this.addObservation,
    required this.chooseFromGallery,
    required this.gallerySubtitle,
    required this.takePhoto,
    required this.cameraSubtitle,
    required this.refresh,
    required this.centerOnUser,
    required this.cats,
    required this.vets,
    required this.shops,
    required this.shelters,
    required this.couldNotLoadPlaceMarkers,
    required this.couldNotLoadCatMarkers,
    required this.couldNotResolveLocation,
    required this.sourceOpenStreetMap,
    required this.sourceMushukistan,
    required this.recent,
    required this.popular,
    required this.nearby,
    required this.needsHelp,
    required this.injured,
    required this.lostPets,
    required this.today,
    required this.month,
    required this.allTime,
    required this.noObservationsYet,
    required this.anonymous,
    required this.unnamedCat,
    required this.openPost,
    required this.like,
    required this.unlike,
    required this.comments,
    required this.myObservations,
    required this.myComments,
    required this.userObservations,
    required this.userComments,
    required this.noCommentsYet,
    required this.noActivityVisible,
    required this.noDescription,
    required this.privacy,
    required this.allowPublicActivityView,
    required this.allowPublicActivityViewSubtitle,
    required this.viewCommentsPrefix,
    required this.viewCommentsSuffix,
    required this.likes,
    required this.leaderboard,
    required this.mostActive,
    required this.mostPopular,
    required this.topHelpers,
    required this.day,
    required this.week,
    required this.noLeaderboardData,
    required this.unnamedUser,
    required this.observations,
    required this.score,
    required this.settings,
    required this.editProfile,
    required this.logout,
    required this.confirmLogoutTitle,
    required this.confirmLogoutMessage,
    required this.cancel,
    required this.registered,
    required this.likesReceived,
    required this.theme,
    required this.themeAuto,
    required this.themeDark,
    required this.themeLight,
    required this.saveChanges,
    required this.changesSaved,
    required this.couldNotSaveChanges,
  });

  final String welcomeBack;
  final String signInToMushukistan;
  final String email;
  final String emailHint;
  final String password;
  final String login;
  final String continueWithGoogle;
  final String createAnAccount;
  final String createAccount;
  final String joinMushukistan;
  final String nameOptional;
  final String register;
  final String alreadyHaveAccount;
  final String language;
  final String emailRequired;
  final String invalidEmail;
  final String passwordRequired;
  final String passwordMin8;
  final String nameTooLong;
  final String verifyEmail;
  final String confirmYourEmail;
  final String verifyEmailWithoutAddress;
  final String verifyEmailWithAddress;
  final String devVerificationHelp;
  final String verifyNow;
  final String resendVerification;
  final String backToLogin;
  final String sessionCheckFailed;
  final String retry;
  final String continueToLogin;
  final String restoringSession;
  final String feed;
  final String map;
  final String add;
  final String leaders;
  final String profile;
  final String addObservation;
  final String chooseFromGallery;
  final String gallerySubtitle;
  final String takePhoto;
  final String cameraSubtitle;
  final String refresh;
  final String centerOnUser;
  final String cats;
  final String vets;
  final String shops;
  final String shelters;
  final String couldNotLoadPlaceMarkers;
  final String couldNotLoadCatMarkers;
  final String couldNotResolveLocation;
  final String sourceOpenStreetMap;
  final String sourceMushukistan;
  final String recent;
  final String popular;
  final String nearby;
  final String needsHelp;
  final String injured;
  final String lostPets;
  final String today;
  final String month;
  final String allTime;
  final String noObservationsYet;
  final String anonymous;
  final String unnamedCat;
  final String openPost;
  final String like;
  final String unlike;
  final String comments;
  final String myObservations;
  final String myComments;
  final String userObservations;
  final String userComments;
  final String noCommentsYet;
  final String noActivityVisible;
  final String noDescription;
  final String privacy;
  final String allowPublicActivityView;
  final String allowPublicActivityViewSubtitle;
  final String viewCommentsPrefix;
  final String viewCommentsSuffix;
  final String likes;
  final String leaderboard;
  final String mostActive;
  final String mostPopular;
  final String topHelpers;
  final String day;
  final String week;
  final String noLeaderboardData;
  final String unnamedUser;
  final String observations;
  final String score;
  final String settings;
  final String editProfile;
  final String logout;
  final String confirmLogoutTitle;
  final String confirmLogoutMessage;
  final String cancel;
  final String registered;
  final String likesReceived;
  final String theme;
  final String themeAuto;
  final String themeDark;
  final String themeLight;
  final String saveChanges;
  final String changesSaved;
  final String couldNotSaveChanges;

  String get acceptTermsAndPrivacy {
    return switch (this) {
      _UzbekStrings() =>
        'Foydalanish shartlari va Maxfiylik siyosatini qabul qiling.',
      _RussianStrings() =>
        'Примите Условия использования и Политику конфиденциальности.',
      _ => 'Accept the Terms of Service and Privacy Policy.',
    };
  }

  String get acceptLegalLeading {
    return switch (this) {
      _UzbekStrings() => 'Men ',
      _RussianStrings() => 'Я принимаю ',
      _ => 'I accept the ',
    };
  }

  String get acceptLegalTrailing {
    return switch (this) {
      _UzbekStrings() => 'ni qabul qilaman.',
      _ => '.',
    };
  }

  String get termsOfService {
    return switch (this) {
      _UzbekStrings() => 'Foydalanish shartlari',
      _RussianStrings() => 'Условия использования',
      _ => 'Terms of Service',
    };
  }

  String get privacyPolicy {
    return switch (this) {
      _UzbekStrings() => 'Maxfiylik siyosati',
      _RussianStrings() => 'Политика конфиденциальности',
      _ => 'Privacy Policy',
    };
  }

  String get aboutAccount {
    return switch (this) {
      _UzbekStrings() => 'Hisob haqida',
      _RussianStrings() => 'Об аккаунте',
      _ => 'About account',
    };
  }

  String get phoneNumber {
    return switch (this) {
      _UzbekStrings() => 'Telefon raqami',
      _RussianStrings() => 'Номер телефона',
      _ => 'Phone number',
    };
  }

  String get notAdded {
    return switch (this) {
      _UzbekStrings() => 'Qo‘shilmagan',
      _RussianStrings() => 'Не добавлен',
      _ => 'Not added',
    };
  }

  String get privacyPolicySummary {
    return switch (this) {
      _UzbekStrings() =>
        'Mushukistan xarita va lenta uchun hisob, profil, ochiq postlar, rasmlar, izohlar, shikoyatlar va joylashuv ma’lumotlarini saqlaydi. Tekshirilgan MVP’da analitika, reklama, push, crash SDK yoki AI funksiyasi yo‘q.',
      _RussianStrings() =>
        'Mushukistan хранит данные аккаунта, профиля, публичные посты, фото, комментарии, жалобы и местоположения для карты и ленты. В проверенном MVP нет аналитики, рекламы, push-уведомлений, crash SDK или AI-функций.',
      _ =>
        'Mushukistan stores account data, profile data, public posts, photos, comments, reports, and locations needed for map and feed features. No analytics, ads, push, crash SDK, or AI feature is included in the verified MVP.',
    };
  }

  String get termsOfServiceSummary {
    return switch (this) {
      _UzbekStrings() =>
        'Mushukistan’dan faqat qonuniy mushuk va yo‘qolgan jonivor kontenti uchun foydalaning. Shaxsiy ma’lumotlar, haqorat, spam, noqonuniy kontent yoki ruxsatsiz mualliflik materiallarini joylamang.',
      _RussianStrings() =>
        'Используйте Mushukistan только для законного контента о кошках и потерянных питомцах, которым вы вправе делиться. Не публикуйте личные данные, оскорбления, спам, незаконный контент или материалы без разрешения правообладателя.',
      _ =>
        'Use Mushukistan only for lawful cat and lost-pet content you have permission to share. Do not post private personal data, harassment, spam, illegal content, or copyrighted material without permission.',
    };
  }

  String get accountDeletion {
    return switch (this) {
      _UzbekStrings() => 'Hisobni o‘chirish',
      _RussianStrings() => 'Удаление аккаунта',
      _ => 'Account deletion',
    };
  }

  String get accountDeletionSummary {
    return switch (this) {
      _UzbekStrings() =>
        'Hisob o‘chirilsa, kirish o‘chadi, profil shaxsiy ma’lumotlari olib tashlanadi, postlar, izohlar va yo‘qolgan jonivor postlari yashiriladi va anonimlashtiriladi, telefon nusxalari hamda layklar o‘chiriladi, media fayllarni tozalashga urinish qilinadi.',
      _RussianStrings() =>
        'Удаление аккаунта отключает вход, удаляет персональные данные профиля, скрывает и анонимизирует ваши посты, комментарии и посты о потерянных питомцах, удаляет сохраненные копии телефона и лайки, а также пытается очистить медиафайлы.',
      _ =>
        'Deleting your account disables login, removes profile personal data, hides and anonymizes your posts, comments, and lost-pet posts, removes copied phone numbers, deletes likes, and attempts media cleanup.',
    };
  }

  String get chooseYourLanguage {
    return switch (this) {
      _UzbekStrings() => 'Tilni tanlang',
      _RussianStrings() => 'Выберите язык',
      _ => 'Choose your language',
    };
  }

  String get chooseLanguageSubtitle {
    return switch (this) {
      _UzbekStrings() =>
        'Mushukistan ichida ishlatmoqchi bo‘lgan tilni tanlang.',
      _RussianStrings() =>
        'Выберите язык, который хотите использовать в Mushukistan.',
      _ => 'Set the language you want to use inside Mushukistan.',
    };
  }

  String get continueAction {
    return switch (this) {
      _UzbekStrings() => 'Davom etish',
      _RussianStrings() => 'Продолжить',
      _ => 'Continue',
    };
  }

  String get welcomeToMushukistan {
    return switch (this) {
      _UzbekStrings() => 'Mushukistanga xush kelibsiz',
      _RussianStrings() => 'Добро пожаловать в Mushukistan',
      _ => 'Welcome to Mushukistan',
    };
  }

  String get welcomeSupportMessage {
    return switch (this) {
      _UzbekStrings() =>
        'Salom! Men Sardorman, Data Science yo‘nalishida o‘qiyman. Bu ilovani yon loyiha sifatida o‘zim yaratdim va xarajatlarini o‘zim qopladim. Ilova butunlay bepul va reklamasiz.',
      _RussianStrings() =>
        'Привет! Я Сардор, студент Data Science. Я создал это приложение как личный проект и финансирую его сам. Оно полностью бесплатное и без рекламы.',
      _ =>
        'Hi there! I’m Sardor, a Data Science student. I built this app as a side project and funded it myself, and it’s completely free and ad-free.',
    };
  }

  String get supportMyWork {
    return switch (this) {
      _UzbekStrings() => 'Ishimni qo‘llab-quvvatlash',
      _RussianStrings() => 'Поддержать мою работу',
      _ => 'Support my work',
    };
  }

  String get supportCardIntro {
    return switch (this) {
      _UzbekStrings() =>
        'Agar ishimni qo‘llab-quvvatlamoqchi bo‘lsangiz, kartam:',
      _RussianStrings() => 'Если хотите поддержать мою работу, вот моя карта:',
      _ => 'If you’d like to support my work, here’s my card:',
    };
  }

  String get startExploring {
    return switch (this) {
      _UzbekStrings() => 'Boshlash',
      _RussianStrings() => 'Начать',
      _ => 'Start exploring',
    };
  }

  String get lostPet {
    return switch (this) {
      _UzbekStrings() => 'Yo‘qolgan jonivor',
      _RussianStrings() => 'Потерянный питомец',
      _ => 'Lost Pet',
    };
  }

  String get catNameLabel {
    return switch (this) {
      _UzbekStrings() => 'Mushuk nomi',
      _RussianStrings() => '\u0418\u043c\u044f \u043a\u043e\u0448\u043a\u0438',
      _ => 'Cat name',
    };
  }

  String get descriptionLabel {
    return switch (this) {
      _UzbekStrings() => 'Tavsif',
      _RussianStrings() => '\u041e\u043f\u0438\u0441\u0430\u043d\u0438\u0435',
      _ => 'Description',
    };
  }

  String get lostPetSubtitle {
    return switch (this) {
      _UzbekStrings() =>
        'Rasmlar va egasining aloqa raqami bilan yo‘qolgan mushukni joylang.',
      _RussianStrings() =>
        'Опубликуйте потерянную кошку с фото и контактом владельца.',
      _ => 'Post a lost cat with photos and owner contact.',
    };
  }

  String get phoneNumberRequired {
    return switch (this) {
      _UzbekStrings() => 'Telefon raqami kerak',
      _RussianStrings() => 'Нужен номер телефона',
      _ => 'Phone number required',
    };
  }

  String get phoneNumberRequiredForLostPet {
    return switch (this) {
      _UzbekStrings() =>
        'Yo‘qolgan jonivorni joylashdan oldin to‘g‘ri O‘zbekiston telefon raqamini qo‘shing. Masalan: +998 99 142 1314.',
      _RussianStrings() =>
        'Добавьте корректный номер телефона Узбекистана перед публикацией потерянного питомца. Например: +998 99 142 1314.',
      _ =>
        'Add a valid Uzbekistan phone number before posting a lost pet. Example: +998 99 142 1314.',
    };
  }

  String get photos {
    return switch (this) {
      _UzbekStrings() => 'Rasmlar',
      _RussianStrings() => 'Фото',
      _ => 'Photos',
    };
  }

  String get addPhotos {
    return switch (this) {
      _UzbekStrings() => 'Rasm qo‘shish',
      _RussianStrings() => 'Добавить фото',
      _ => 'Add photos',
    };
  }

  String get petsName {
    return switch (this) {
      _UzbekStrings() => 'Jonivorning ismi',
      _RussianStrings() => 'Имя питомца',
      _ => "Pet's name",
    };
  }

  String get enterPetsName {
    return switch (this) {
      _UzbekStrings() => 'Jonivorning ismini kiriting.',
      _RussianStrings() => 'Введите имя питомца.',
      _ => "Enter the pet's name.",
    };
  }

  String get lastSeen {
    return switch (this) {
      _UzbekStrings() => 'Oxirgi ko‘rilgan joy',
      _RussianStrings() => 'Где видели в последний раз',
      _ => 'Last seen',
    };
  }

  String get additionalInformation {
    return switch (this) {
      _UzbekStrings() => 'Qo‘shimcha ma’lumot',
      _RussianStrings() => 'Дополнительная информация',
      _ => 'Additional information',
    };
  }

  String get publishLostPet {
    return switch (this) {
      _UzbekStrings() => 'Yo‘qolgan jonivorni joylash',
      _RussianStrings() => 'Опубликовать потерянного питомца',
      _ => 'Publish lost pet',
    };
  }

  String get addAtLeastOnePhoto {
    return switch (this) {
      _UzbekStrings() => 'Kamida bitta rasm qo‘shing.',
      _RussianStrings() => 'Добавьте хотя бы одно фото.',
      _ => 'Add at least one photo.',
    };
  }

  String get pointLastSeenLocation {
    return switch (this) {
      _UzbekStrings() => 'Xaritada oxirgi ko‘rilgan joyni belgilang.',
      _RussianStrings() =>
        'Укажите на карте, где питомца видели в последний раз.',
      _ => 'Point the last-seen location on the map.',
    };
  }

  String get confirmPhonePublic {
    return switch (this) {
      _UzbekStrings() => 'Telefon raqamingiz ochiq ko‘rsatilishini tasdiqlang.',
      _RussianStrings() =>
        'Подтвердите, что ваш номер телефона можно показать публично.',
      _ => 'Confirm that your phone number may be shown publicly.',
    };
  }

  String get phonePublicConsent {
    return switch (this) {
      _UzbekStrings() =>
        'Profilimdagi telefon raqamini bu yo‘qolgan jonivor postida ochiq ko‘rsatish.',
      _RussianStrings() =>
        'Публично показать номер телефона из моего профиля в этом посте о потерянном питомце.',
      _ => 'Show my profile phone number publicly on this lost-pet post.',
    };
  }

  String get phonePublicConsentSubtitle {
    return switch (this) {
      _UzbekStrings() =>
        'Lenta yoki yo‘qolgan jonivor sahifasini ko‘rgan odamlar shu raqamga qo‘ng‘iroq qilishi mumkin.',
      _RussianStrings() =>
        'Люди, которые увидят ленту или страницу потерянного питомца, смогут позвонить на этот номер.',
      _ => 'People who view the feed or lost-pet page can call this number.',
    };
  }

  String get tapMapForLastSeen {
    return switch (this) {
      _UzbekStrings() => 'Jonivor oxirgi ko‘rilgan joyni xaritada bosing.',
      _RussianStrings() =>
        'Нажмите на карту, где питомца видели в последний раз.',
      _ => 'Tap the map to point where the pet was last seen.',
    };
  }

  String get lastSeenLocationSelected {
    return switch (this) {
      _UzbekStrings() => 'Oxirgi ko‘rilgan joy tanlandi.',
      _RussianStrings() => 'Место последнего обнаружения выбрано.',
      _ => 'Last-seen location selected.',
    };
  }

  String get contactOwner {
    return switch (this) {
      _UzbekStrings() => 'Egasi bilan bog‘lanish',
      _RussianStrings() => 'Связаться с владельцем',
      _ => 'Contact Owner',
    };
  }

  String get ownerPhone {
    return switch (this) {
      _UzbekStrings() => 'Egasining telefoni',
      _RussianStrings() => 'Телефон владельца',
      _ => 'Owner phone',
    };
  }

  String get viewOnMap {
    return switch (this) {
      _UzbekStrings() => 'Xaritada ko‘rish',
      _RussianStrings() => 'Показать на карте',
      _ => 'View on map',
    };
  }

  String get adoptionHelp {
    return switch (this) {
      _UzbekStrings() => 'Mushuk asrab olish bo‘yicha yordam',
      _RussianStrings() => 'Помощь по усыновлению кошки',
      _ => 'Cat adoption help',
    };
  }

  String get adoptionHelpTooltip {
    return switch (this) {
      _UzbekStrings() => 'Mushukni qonuniy va xavfsiz asrab olish',
      _RussianStrings() => 'Как законно и безопасно взять кошку',
      _ => 'How to adopt a cat legally and safely',
    };
  }

  String get adoptionHelpDisclaimer {
    return switch (this) {
      _UzbekStrings() =>
        'Bu umumiy ma’lumot. Shaxsiy vaziyatingiz uchun tuman/shahar davlat veterinariya xizmati yoki yurist bilan tekshiring.',
      _RussianStrings() =>
        'Это общая информация. По вашей ситуации уточните требования в районной/городской государственной ветеринарной службе или у юриста.',
      _ =>
        'This is general information. Confirm requirements for your situation with your district/city state veterinary service or a lawyer.',
    };
  }

  String get adoptionBeforeYouTakeCat {
    return switch (this) {
      _UzbekStrings() => 'Mushukni olib ketishdan oldin',
      _RussianStrings() => 'Перед тем как забрать кошку',
      _ => 'Before you take the cat',
    };
  }

  String get adoptionVetProcedure {
    return switch (this) {
      _UzbekStrings() => 'Veterinariya jarayoni',
      _RussianStrings() => 'Ветеринарная процедура',
      _ => 'Veterinary procedure',
    };
  }

  String get adoptionLegalCareRules {
    return switch (this) {
      _UzbekStrings() => 'Uyda saqlash qoidalari',
      _RussianStrings() => 'Правила содержания дома',
      _ => 'Home-keeping rules',
    };
  }

  String get adoptionOfficialSources {
    return switch (this) {
      _UzbekStrings() => 'Rasmiy manbalar',
      _RussianStrings() => 'Официальные источники',
      _ => 'Official sources',
    };
  }

  String get adoptionSourceKeepingRules {
    return switch (this) {
      _UzbekStrings() => 'Itlar va mushuklarni saqlash qoidalari',
      _RussianStrings() => 'Правила содержания собак и кошек',
      _ => 'Rules for keeping dogs and cats',
    };
  }

  String get adoptionSourceVetPassport {
    return switch (this) {
      _UzbekStrings() => 'Veterinariya pasporti va identifikatsiya',
      _RussianStrings() => 'Ветеринарный паспорт и идентификация',
      _ => 'Veterinary passport and identification',
    };
  }

  String get adoptionSourceStrayAnimals {
    return switch (this) {
      _UzbekStrings() => 'Qarovsiz hayvonlarni tutish xizmatlari',
      _RussianStrings() => 'Службы отлова безнадзорных животных',
      _ => 'Stray animal catching services',
    };
  }

  String get deleteAccount {
    return switch (this) {
      _UzbekStrings() => 'Hisobni o‘chirish',
      _RussianStrings() => 'Удалить аккаунт',
      _ => 'Delete account',
    };
  }

  String get confirmDeleteAccountTitle {
    return switch (this) {
      _UzbekStrings() => 'Hisob o‘chirilsinmi?',
      _RussianStrings() => 'Удалить аккаунт?',
      _ => 'Delete account?',
    };
  }

  String get confirmDeleteAccountMessage {
    return switch (this) {
      _UzbekStrings() =>
        'Hisobingiz o‘chirib qo‘yiladi va sessiyangiz tugaydi. Mavjud kontent moderatsiya tarixi uchun saqlanishi mumkin.',
      _RussianStrings() =>
        'Ваш аккаунт будет отключен, а текущая сессия завершится. Существующий контент может сохраниться для модерации.',
      _ =>
        'Your account will be deactivated and your current session will end. Existing content may remain for moderation history.',
    };
  }

  String get accountDeleted {
    return switch (this) {
      _UzbekStrings() => 'Hisob o‘chirildi.',
      _RussianStrings() => 'Аккаунт удален.',
      _ => 'Account deleted.',
    };
  }

  String get couldNotDeleteAccount {
    return switch (this) {
      _UzbekStrings() => 'Hisobni o‘chirib bo‘lmadi.',
      _RussianStrings() => 'Не удалось удалить аккаунт.',
      _ => 'Could not delete account.',
    };
  }

  String get filters {
    return switch (this) {
      _UzbekStrings() => 'Filtrlar',
      _RussianStrings() => 'Фильтры',
      _ => 'Filters',
    };
  }

  String get applyFilters {
    return switch (this) {
      _UzbekStrings() => 'Filtrlarni qo‘llash',
      _RussianStrings() => 'Применить фильтры',
      _ => 'Apply filters',
    };
  }

  String showingMapItems({
    required int catCount,
    required int placeCount,
    required double latitude,
    required double longitude,
  }) {
    return switch (this) {
      _UzbekStrings() =>
        '$catCount ta mushuk va $placeCount ta joy ko‘rsatilmoqda: '
            '${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)}',
      _RussianStrings() =>
        'Показано кошек: $catCount, мест: $placeCount рядом с '
            '${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)}',
      _ => 'Showing $catCount cats and $placeCount places near '
          '${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)}',
    };
  }

  String viewComments(int count) {
    return '$viewCommentsPrefix$count$viewCommentsSuffix';
  }

  static AppStrings forLanguage(AppLanguage language) {
    return switch (language) {
      AppLanguage.uzbek => const _UzbekStrings(),
      AppLanguage.russian => const _RussianStrings(),
      AppLanguage.english => const _EnglishStrings(),
    };
  }
}

class _EnglishStrings extends AppStrings {
  const _EnglishStrings()
      : super(
          welcomeBack: 'Welcome back',
          signInToMushukistan: 'Sign in to Mushukistan',
          email: 'Email',
          emailHint: 'user@example.com',
          password: 'Password',
          login: 'Login',
          continueWithGoogle: 'Continue with Google',
          createAnAccount: 'Create an account',
          createAccount: 'Create account',
          joinMushukistan: 'Join Mushukistan',
          nameOptional: 'Name (optional)',
          register: 'Register',
          alreadyHaveAccount: 'Already have an account?',
          language: 'Language',
          emailRequired: 'Email is required.',
          invalidEmail: 'Enter a valid email address.',
          passwordRequired: 'Password is required.',
          passwordMin8: 'Password must be at least 8 characters.',
          nameTooLong: 'Name must be 100 characters or fewer.',
          verifyEmail: 'Verify email',
          confirmYourEmail: 'Confirm your email',
          verifyEmailWithoutAddress:
              'We need to confirm your email address before you can sign in.',
          verifyEmailWithAddress:
              'We need to confirm {email} before you can sign in.',
          devVerificationHelp:
              'Open the verification link from your email to finish confirming your account.',
          verifyNow: 'Verify now',
          resendVerification: 'Resend verification',
          backToLogin: 'Back to login',
          sessionCheckFailed: 'Session check failed.',
          retry: 'Retry',
          continueToLogin: 'Continue to login',
          restoringSession: 'Restoring session...',
          feed: 'Feed',
          map: 'Map',
          add: 'Add',
          leaders: 'Leaders',
          profile: 'Profile',
          addObservation: 'Add observation',
          chooseFromGallery: 'Choose from gallery',
          gallerySubtitle: 'Publishes to the feed without a map location.',
          takePhoto: 'Take photo',
          cameraSubtitle: 'Captures current location for the map.',
          refresh: 'Refresh',
          centerOnUser: 'Center on user',
          cats: 'Cats',
          vets: 'Vets',
          shops: 'Shops',
          shelters: 'Shelters',
          couldNotLoadPlaceMarkers: 'Could not load place markers.',
          couldNotLoadCatMarkers: 'Could not load cat markers.',
          couldNotResolveLocation: 'Could not resolve location.',
          sourceOpenStreetMap: 'Source: OpenStreetMap',
          sourceMushukistan: 'Source: Mushukistan verified data',
          recent: 'Recent',
          popular: 'Popular',
          nearby: 'Nearby',
          needsHelp: 'Needs help',
          injured: 'Injured',
          lostPets: 'Lost pets',
          today: 'Today',
          month: 'Month',
          allTime: 'All time',
          noObservationsYet: 'No observations yet.',
          anonymous: 'Anonymous',
          unnamedCat: 'Unnamed cat',
          openPost: 'Open post',
          like: 'Like',
          unlike: 'Unlike',
          comments: 'Comments',
          myObservations: 'My observations',
          myComments: 'My comments',
          userObservations: 'Observations',
          userComments: 'Comments',
          noCommentsYet: 'No comments yet.',
          noActivityVisible: 'This user has hidden their activity.',
          noDescription: 'No description',
          privacy: 'Privacy',
          allowPublicActivityView: 'Allow others to view my activity',
          allowPublicActivityViewSubtitle:
              'People can open your observations and comments from your profile.',
          viewCommentsPrefix: 'View ',
          viewCommentsSuffix: ' comments',
          likes: 'likes',
          leaderboard: 'Leaderboard',
          mostActive: 'Most active',
          mostPopular: 'Most popular',
          topHelpers: 'Top helpers',
          day: 'Day',
          week: 'Week',
          noLeaderboardData: 'No leaderboard data yet.',
          unnamedUser: 'Unnamed user',
          observations: 'observations',
          score: 'score',
          settings: 'Settings',
          editProfile: 'Edit profile',
          logout: 'Logout',
          confirmLogoutTitle: 'Log out?',
          confirmLogoutMessage:
              'You will need to sign in again to continue using your account.',
          cancel: 'Cancel',
          registered: 'Registered',
          likesReceived: 'Likes received',
          theme: 'Theme',
          themeAuto: 'Auto',
          themeDark: 'Dark',
          themeLight: 'Light',
          saveChanges: 'Save changes',
          changesSaved: 'Changes saved.',
          couldNotSaveChanges: 'Could not save changes.',
        );
}

class _UzbekStrings extends AppStrings {
  const _UzbekStrings()
      : super(
          welcomeBack: 'Xush kelibsiz',
          signInToMushukistan: 'Mushukistanga kiring',
          email: 'Email',
          emailHint: 'user@example.com',
          password: 'Parol',
          login: 'Kirish',
          continueWithGoogle: 'Google bilan davom etish',
          createAnAccount: 'Hisob yaratish',
          createAccount: 'Hisob yaratish',
          joinMushukistan: 'Mushukistanga qo‘shiling',
          nameOptional: 'Ism (ixtiyoriy)',
          register: 'Ro‘yxatdan o‘tish',
          alreadyHaveAccount: 'Hisobingiz bormi?',
          language: 'Til',
          emailRequired: 'Email kiritilishi kerak.',
          invalidEmail: 'To‘g‘ri email manzil kiriting.',
          passwordRequired: 'Parol kiritilishi kerak.',
          passwordMin8: 'Parol kamida 8 ta belgidan iborat bo‘lishi kerak.',
          nameTooLong: 'Ism 100 ta belgidan oshmasligi kerak.',
          verifyEmail: 'Emailni tasdiqlash',
          confirmYourEmail: 'Emailingizni tasdiqlang',
          verifyEmailWithoutAddress:
              'Kirishdan oldin email manzilingizni tasdiqlashimiz kerak.',
          verifyEmailWithAddress:
              'Kirishdan oldin {email} manzilini tasdiqlashimiz kerak.',
          devVerificationHelp:
              'Bu development versiyada tasdiqlash havolasi backend orqali chiqariladi. Token mavjud bo‘lsa, quyidagi tezkor tasdiqlashdan foydalaning.',
          verifyNow: 'Hozir tasdiqlash',
          resendVerification: 'Tasdiqlashni qayta yuborish',
          backToLogin: 'Kirishga qaytish',
          sessionCheckFailed: 'Sessiyani tekshirib bo‘lmadi.',
          retry: 'Qayta urinish',
          continueToLogin: 'Kirishga o‘tish',
          restoringSession: 'Sessiya tiklanmoqda...',
          feed: 'Lenta',
          map: 'Xarita',
          add: 'Qo‘shish',
          leaders: 'Yetakchilar',
          profile: 'Profil',
          addObservation: 'Kuzatuv qo‘shish',
          chooseFromGallery: 'Galereyadan tanlash',
          gallerySubtitle: 'Xaritadagi joylashuvsiz lentaga joylanadi.',
          takePhoto: 'Rasmga olish',
          cameraSubtitle: 'Xarita uchun joriy joylashuvni oladi.',
          refresh: 'Yangilash',
          centerOnUser: 'Joylashuvimga olib borish',
          cats: 'Mushuklar',
          vets: 'Veterinarlar',
          shops: 'Do‘konlar',
          shelters: 'Shelterlar',
          couldNotLoadPlaceMarkers: 'Joy markerlarini yuklab bo‘lmadi.',
          couldNotLoadCatMarkers: 'Mushuk markerlarini yuklab bo‘lmadi.',
          couldNotResolveLocation: 'Joylashuvni aniqlab bo‘lmadi.',
          sourceOpenStreetMap: 'Manba: OpenStreetMap',
          sourceMushukistan: 'Manba: Mushukistan tasdiqlangan ma’lumotlari',
          recent: 'Yangi',
          popular: 'Mashhur',
          nearby: 'Yaqin',
          needsHelp: 'Yordam kerak',
          injured: 'Jarohatlangan',
          lostPets: 'Yo‘qolgan uy hayvonlari',
          today: 'Bugun',
          month: 'Oy',
          allTime: 'Hammasi',
          noObservationsYet: 'Hali kuzatuvlar yo‘q.',
          anonymous: 'Anonim',
          unnamedCat: 'Nomsiz mushuk',
          openPost: 'Postni ochish',
          like: 'Layk',
          unlike: 'Laykni olish',
          comments: 'Izohlar',
          myObservations: 'Kuzatuvlarim',
          myComments: 'Izohlarim',
          userObservations: 'Kuzatuvlar',
          userComments: 'Izohlar',
          noCommentsYet: 'Hali izohlar yo‘q.',
          noActivityVisible: 'Bu foydalanuvchi faolligini ko‘rsatishni yopgan.',
          noDescription: 'Tavsif yo‘q',
          privacy: 'Maxfiylik',
          allowPublicActivityView:
              'Boshqalar faolligimni ko‘rishiga ruxsat berish',
          allowPublicActivityViewSubtitle:
              'Odamlar profilingizdan kuzatuvlaringiz va izohlaringizni ochishi mumkin.',
          viewCommentsPrefix: '',
          viewCommentsSuffix: ' ta izohni ko‘rish',
          likes: 'layk',
          leaderboard: 'Yetakchilar',
          mostActive: 'Eng faol',
          mostPopular: 'Eng mashhur',
          topHelpers: 'Eng yaxshi yordamchilar',
          day: 'Kun',
          week: 'Hafta',
          noLeaderboardData: 'Hali yetakchilar ma’lumoti yo‘q.',
          unnamedUser: 'Nomsiz foydalanuvchi',
          observations: 'kuzatuvlar',
          score: 'ball',
          settings: 'Sozlamalar',
          editProfile: 'Profilni tahrirlash',
          logout: 'Chiqish',
          confirmLogoutTitle: 'Chiqasizmi?',
          confirmLogoutMessage:
              'Hisobingizdan foydalanishda davom etish uchun qayta kirishingiz kerak bo‘ladi.',
          cancel: 'Bekor qilish',
          registered: 'Ro‘yxatdan o‘tgan',
          likesReceived: 'Olingan layklar',
          theme: 'Mavzu',
          themeAuto: 'Avto',
          themeDark: 'Qorong‘i',
          themeLight: 'Yorug‘',
          saveChanges: 'O‘zgarishlarni saqlash',
          changesSaved: 'O‘zgarishlar saqlandi.',
          couldNotSaveChanges: 'O‘zgarishlarni saqlab bo‘lmadi.',
        );
}

class _RussianStrings extends AppStrings {
  const _RussianStrings()
      : super(
          welcomeBack: 'С возвращением',
          signInToMushukistan: 'Войти в Mushukistan',
          email: 'Email',
          emailHint: 'user@example.com',
          password: 'Пароль',
          login: 'Войти',
          continueWithGoogle: 'Продолжить с Google',
          createAnAccount: 'Создать аккаунт',
          createAccount: 'Создать аккаунт',
          joinMushukistan: 'Присоединиться к Mushukistan',
          nameOptional: 'Имя (необязательно)',
          register: 'Зарегистрироваться',
          alreadyHaveAccount: 'Уже есть аккаунт?',
          language: 'Язык',
          emailRequired: 'Укажите email.',
          invalidEmail: 'Введите корректный email.',
          passwordRequired: 'Укажите пароль.',
          passwordMin8: 'Пароль должен быть не короче 8 символов.',
          nameTooLong: 'Имя должно быть не длиннее 100 символов.',
          verifyEmail: 'Подтвердите email',
          confirmYourEmail: 'Подтвердите ваш email',
          verifyEmailWithoutAddress:
              'Перед входом нужно подтвердить ваш email.',
          verifyEmailWithAddress: 'Перед входом нужно подтвердить {email}.',
          devVerificationHelp:
              'В этой development-сборке ссылка подтверждения выводится backend-ом. Если доступен token, используйте быстрое подтверждение ниже.',
          verifyNow: 'Подтвердить сейчас',
          resendVerification: 'Отправить подтверждение снова',
          backToLogin: 'Назад ко входу',
          sessionCheckFailed: 'Не удалось проверить сессию.',
          retry: 'Повторить',
          continueToLogin: 'Перейти ко входу',
          restoringSession: 'Восстановление сессии...',
          feed: 'Лента',
          map: 'Карта',
          add: 'Добавить',
          leaders: 'Лидеры',
          profile: 'Профиль',
          addObservation: 'Добавить наблюдение',
          chooseFromGallery: 'Выбрать из галереи',
          gallerySubtitle: 'Публикуется в ленту без точки на карте.',
          takePhoto: 'Сделать фото',
          cameraSubtitle: 'Сохраняет текущую геопозицию для карты.',
          refresh: 'Обновить',
          centerOnUser: 'К моему местоположению',
          cats: 'Кошки',
          vets: 'Ветклиники',
          shops: 'Магазины',
          shelters: 'Приюты',
          couldNotLoadPlaceMarkers: 'Не удалось загрузить места.',
          couldNotLoadCatMarkers: 'Не удалось загрузить кошек.',
          couldNotResolveLocation: 'Не удалось определить местоположение.',
          sourceOpenStreetMap: 'Источник: OpenStreetMap',
          sourceMushukistan: 'Источник: проверенные данные Mushukistan',
          recent: 'Новые',
          popular: 'Популярные',
          nearby: 'Рядом',
          needsHelp: 'Нужна помощь',
          injured: 'Раненые',
          lostPets: 'Потерянные питомцы',
          today: 'Сегодня',
          month: 'Месяц',
          allTime: 'Все время',
          noObservationsYet: 'Наблюдений пока нет.',
          anonymous: 'Аноним',
          unnamedCat: 'Кошка без имени',
          openPost: 'Открыть пост',
          like: 'Лайк',
          unlike: 'Убрать лайк',
          comments: 'Комментарии',
          myObservations: 'Мои наблюдения',
          myComments: 'Мои комментарии',
          userObservations: 'Наблюдения',
          userComments: 'Комментарии',
          noCommentsYet: 'Комментариев пока нет.',
          noActivityVisible: 'Этот пользователь скрыл свою активность.',
          noDescription: 'Нет описания',
          privacy: 'Приватность',
          allowPublicActivityView: 'Разрешить другим видеть мою активность',
          allowPublicActivityViewSubtitle:
              'Люди смогут открывать ваши наблюдения и комментарии из профиля.',
          viewCommentsPrefix: 'Показать комментарии: ',
          viewCommentsSuffix: '',
          likes: 'лайков',
          leaderboard: 'Лидеры',
          mostActive: 'Самые активные',
          mostPopular: 'Самые популярные',
          topHelpers: 'Лучшие помощники',
          day: 'День',
          week: 'Неделя',
          noLeaderboardData: 'Данных лидерборда пока нет.',
          unnamedUser: 'Пользователь без имени',
          observations: 'наблюдений',
          score: 'баллы',
          settings: 'Настройки',
          editProfile: 'Редактировать профиль',
          logout: 'Выйти',
          confirmLogoutTitle: 'Выйти?',
          confirmLogoutMessage:
              'Чтобы продолжить пользоваться аккаунтом, нужно будет войти снова.',
          cancel: 'Отмена',
          registered: 'Дата регистрации',
          likesReceived: 'Получено лайков',
          theme: 'Тема',
          themeAuto: 'Авто',
          themeDark: 'Темная',
          themeLight: 'Светлая',
          saveChanges: 'Сохранить изменения',
          changesSaved: 'Изменения сохранены.',
          couldNotSaveChanges: 'Не удалось сохранить изменения.',
        );
}
