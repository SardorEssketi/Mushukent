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

  String get nameRequired {
    return switch (this) {
      _UzbekStrings() => 'Ism kiritilishi kerak.',
      _RussianStrings() => 'Укажите имя.',
      _ => 'Name is required.',
    };
  }

  String get home {
    return switch (this) {
      _UzbekStrings() => 'Bosh sahifa',
      _RussianStrings() => 'Главная',
      _ => 'Home',
    };
  }

  String get community {
    return switch (this) {
      _UzbekStrings() => 'Hamjamiyat',
      _RussianStrings() => 'Сообщество',
      _ => 'Community',
    };
  }

  String get communitySubtitle {
    return switch (this) {
      _UzbekStrings() =>
        'Mushuklarga kuzatuvlar, izohlar va yordam orqali hissa qo‘shayotganlar eʼtirofi.',
      _RussianStrings() =>
        'Признание людей, которые помогают кошкам наблюдениями, комментариями и поддержкой.',
      _ =>
        'Recognition for people helping cats through observations, comments, and support.',
    };
  }

  String get createInMushukistan {
    return switch (this) {
      _UzbekStrings() => 'Mushukistanda yaratish',
      _RussianStrings() => 'Создать в Mushukistan',
      _ => 'Create in Mushukistan',
    };
  }

  String get chooseShareType {
    return switch (this) {
      _UzbekStrings() =>
        'Ulashmoqchi bo‘lgan mushuk yordami yoki yangilik turini tanlang.',
      _RussianStrings() =>
        'Выберите тип помощи кошке или обновления, которым хотите поделиться.',
      _ => 'Choose the kind of cat help or update you want to share.',
    };
  }

  String get catObservationAddSubtitle {
    return switch (this) {
      _UzbekStrings() =>
        'Mushuk rasmlarini qo‘shing, keyin joriy joylashuvni tanlang, xaritada belgilang yoki joylashuvsiz davom eting.',
      _RussianStrings() =>
        'Добавьте фото кошки, затем выберите текущее место, отметьте на карте или продолжите без места.',
      _ =>
        'Add cat photos, then choose current location, mark on map, or skip location.',
    };
  }

  String get lostPetAddSubtitle {
    return switch (this) {
      _UzbekStrings() =>
        'Egasi bilan aloqa va oxirgi ko‘rilgan joyi bor alohida eʼlon yarating.',
      _RussianStrings() =>
        'Создайте отдельное объявление с контактом владельца и местом последнего обнаружения.',
      _ => 'Create a distinct alert with owner contact and last-seen location.',
    };
  }

  String get adoptionAddSubtitle {
    return switch (this) {
      _UzbekStrings() =>
        'Aloqa maʼlumotlari bilan alohida yangi uy topish postini yarating.',
      _RussianStrings() =>
        'Создайте отдельный пост о поиске дома с контактными данными.',
      _ => 'Create a separate rehoming post with contact details.',
    };
  }

  String get phoneNumberRequiredForAdoption {
    return switch (this) {
      _UzbekStrings() =>
        'Yangi uy topish postini yaratishdan oldin telefon raqamingizni qo‘shing, shunda odamlar siz bilan bog‘lana oladi.',
      _RussianStrings() =>
        'Добавьте номер телефона перед созданием поста о пристройстве, чтобы люди могли связаться с вами.',
      _ =>
        'Add a phone number before creating an adoption post so people can reach you.',
    };
  }

  String feedSectionTitle(String mode) {
    return switch (mode) {
      'lost_pets' => lostPets,
      'adoption' => findANewHome,
      'needs_help' => switch (this) {
          _UzbekStrings() => 'Yordam kerak mushuklar',
          _RussianStrings() => 'Кошки, которым нужна помощь',
          _ => 'Cats that may need help',
        },
      'popular' => switch (this) {
          _UzbekStrings() => 'Hamjamiyatda mashhur',
          _RussianStrings() => 'Популярное в сообществе',
          _ => 'Popular in the community',
        },
      _ => switch (this) {
          _UzbekStrings() => 'Mushukistandagi so‘nggi yangiliklar',
          _RussianStrings() => 'Новое в Mushukistan',
          _ => 'Latest from Mushukistan',
        },
    };
  }

  String feedSectionSubtitle(String mode) {
    return switch (mode) {
      'lost_pets' => switch (this) {
          _UzbekStrings() =>
            'Egasi bilan aloqa va oxirgi ko‘rilgan hududi bor tanish eʼlonlar.',
          _RussianStrings() =>
            'Узнаваемые объявления с контактом владельца и районом последнего обнаружения.',
          _ => 'Recognizable alerts with owner contact and last-seen areas.',
        },
      'adoption' => switch (this) {
          _UzbekStrings() =>
            'Yaxshi uy kerak bo‘lgan mushuklar uchun alohida postlar.',
          _RussianStrings() =>
            'Отдельные посты о кошках, которым нужен хороший дом.',
          _ => 'Separate rehoming posts for cats who need a good home.',
        },
      'needs_help' => switch (this) {
          _UzbekStrings() =>
            'Ko‘ngillilar eʼtiboriga muhtoj bo‘lishi mumkin bo‘lgan kuzatuvlar.',
          _RussianStrings() =>
            'Наблюдения сообщества, которым может понадобиться внимание волонтеров.',
          _ => 'Community observations that may need volunteer attention.',
        },
      'popular' => switch (this) {
          _UzbekStrings() =>
            'Odamlar eng ko‘p munosabat bildirayotgan postlar.',
          _RussianStrings() => 'Посты, на которые люди реагируют чаще всего.',
          _ => 'Posts people are responding to most.',
        },
      _ => switch (this) {
          _UzbekStrings() =>
            'Mushuklarga yordam berayotgan odamlardan so‘nggi kuzatuvlar, hikoyalar va yangiliklar.',
          _RussianStrings() =>
            'Свежие наблюдения, истории и обновления от людей, помогающих кошкам.',
          _ =>
            'Recent sightings, stories, and updates from people helping cats.',
        },
    };
  }

  String get emptyFeedMessage {
    return switch (this) {
      _UzbekStrings() =>
        'Hamjamiyatni boshlashga yordam berish uchun kuzatuv, yo‘qolgan jonivor eʼloni yoki yangi uy topish postini ulashing.',
      _RussianStrings() =>
        'Поделитесь наблюдением, объявлением о потерянном питомце или постом о пристройстве, чтобы помочь сообществу начать.',
      _ =>
        'Share an observation, lost-pet alert, or rehoming post to help the community start here.',
    };
  }

  String get couldNotLoadSection {
    return switch (this) {
      _UzbekStrings() => 'Bu bo‘limni yuklab bo‘lmadi',
      _RussianStrings() => 'Не удалось загрузить этот раздел',
      _ => 'Could not load this section',
    };
  }

  String get googleLegalConsentTitle {
    return switch (this) {
      _UzbekStrings() => 'Davom etishdan oldin',
      _RussianStrings() => 'Перед продолжением',
      _ => 'Before you continue',
    };
  }

  String get googleLegalConsentMessage {
    return switch (this) {
      _UzbekStrings() =>
        'Google hisobingiz bilan Mushukistan hisobini yaratish uchun huquqiy hujjatlarni qabul qiling.',
      _RussianStrings() =>
        'Примите юридические документы, чтобы создать аккаунт Mushukistan через Google.',
      _ =>
        'Accept the legal documents to create your Mushukistan account with Google.',
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

  String get create {
    return switch (this) {
      _UzbekStrings() => 'Yaratish',
      _RussianStrings() => 'Создать',
      _ => 'Create',
    };
  }

  String get whatAreYouCreating {
    return switch (this) {
      _UzbekStrings() => 'Nima yaratmoqchisiz?',
      _RussianStrings() => 'Что вы создаете?',
      _ => 'What are you creating?',
    };
  }

  String get chooseTypeFirst {
    return switch (this) {
      _UzbekStrings() =>
        'Avval turini tanlang, shunda Mushukistan faqat kerakli maʼlumotlarni soʻraydi.',
      _RussianStrings() =>
        'Сначала выберите тип, чтобы Mushukistan запросил только нужные данные.',
      _ =>
        'Choose the right type first so Mushukistan can ask only for the details that matter.',
    };
  }

  String get catObservation {
    return switch (this) {
      _UzbekStrings() => 'Mushuk kuzatuvi',
      _RussianStrings() => 'Наблюдение за кошкой',
      _ => 'Cat observation',
    };
  }

  String get catObservationSubtitle {
    return switch (this) {
      _UzbekStrings() =>
        'Mushuk rasmlarini qoʻshing, kerak boʻlsa joylashuvni belgilang va yordam kerak mushuklarni ko‘rsating.',
      _RussianStrings() =>
        'Добавьте фото кошки, при необходимости укажите место и отметьте кошек, которым нужна помощь.',
      _ =>
        'Add cat photos, attach a location if useful, and tag cats that need help.',
    };
  }

  String get lostPetAlert {
    return switch (this) {
      _UzbekStrings() => 'Yoʻqolgan jonivor eʼloni',
      _RussianStrings() => 'Объявление о потерянном питомце',
      _ => 'Lost pet alert',
    };
  }

  String get lostPetAlertSubtitle {
    return switch (this) {
      _UzbekStrings() =>
        'Jonivor rasmlari, oxirgi koʻrilgan joy, holat va egasining aloqasi.',
      _RussianStrings() =>
        'Фото питомца, последнее место, статус и контакт владельца.',
      _ => 'Pet photos, last-seen map point, status, and owner contact.',
    };
  }

  String get findANewHome {
    return switch (this) {
      _UzbekStrings() => 'Yangi uy topish',
      _RussianStrings() => 'Найти новый дом',
      _ => 'Find a new home',
    };
  }

  String get findANewHomeSubtitle {
    return switch (this) {
      _UzbekStrings() =>
        'Rasmlar, tavsif va egasining aloqasi bilan alohida uy topish posti. Xarita kerak emas.',
      _RussianStrings() =>
        'Отдельный пост о пристройстве с фото, описанием и контактом владельца. Карта не нужна.',
      _ =>
        'A separate rehoming post with photos, description, and owner contact. No map required.',
    };
  }

  String get preparingPhotoForUpload {
    return switch (this) {
      _UzbekStrings() => 'Rasm yuklashga tayyorlanmoqda...',
      _RussianStrings() => 'Фото готовится к загрузке...',
      _ => 'Preparing photo for upload...',
    };
  }

  String couldNotPreparePhoto(Object error) {
    return switch (this) {
      _UzbekStrings() => 'Rasmni tayyorlab boʻlmadi: $error',
      _RussianStrings() => 'Не удалось подготовить фото: $error',
      _ => 'Could not prepare photo: $error',
    };
  }

  String get continueDraft {
    return switch (this) {
      _UzbekStrings() => 'Qoralamani davom ettirish',
      _RussianStrings() => 'Продолжить черновик',
      _ => 'Continue draft',
    };
  }

  String get deleteDraft {
    return switch (this) {
      _UzbekStrings() => 'Qoralamani oʻchirish',
      _RussianStrings() => 'Удалить черновик',
      _ => 'Delete draft',
    };
  }

  String get draftDeleted {
    return switch (this) {
      _UzbekStrings() => 'Qoralama oʻchirildi.',
      _RussianStrings() => 'Черновик удален.',
      _ => 'Draft deleted.',
    };
  }

  String get addCatPhotos {
    return switch (this) {
      _UzbekStrings() => 'Mushuk rasmlarini qoʻshish',
      _RussianStrings() => 'Добавить фото кошки',
      _ => 'Add cat photos',
    };
  }

  String get selectUpToFivePhotos {
    return switch (this) {
      _UzbekStrings() => 'Besh tagacha rasm tanlang.',
      _RussianStrings() => 'Выберите до пяти фото.',
      _ => 'Select up to five photos.',
    };
  }

  String get takeAPhoto {
    return switch (this) {
      _UzbekStrings() => 'Rasmga olish',
      _RussianStrings() => 'Сделать фото',
      _ => 'Take a photo',
    };
  }

  String get useCameraThenChooseLocation {
    return switch (this) {
      _UzbekStrings() => 'Kameradan foydalaning, keyin joylashuvni tanlang.',
      _RussianStrings() => 'Используйте камеру, затем выберите место.',
      _ => 'Use the camera, then choose location.',
    };
  }

  String get deleteDraftTitle {
    return switch (this) {
      _UzbekStrings() => 'Qoralama oʻchirilsinmi?',
      _RussianStrings() => 'Удалить черновик?',
      _ => 'Delete draft?',
    };
  }

  String get deleteDraftMessage {
    return switch (this) {
      _UzbekStrings() =>
        'Bu qoralamadagi tanlangan rasmlar, joylashuv, tavsif va mushuk tanlovini olib tashlaydi.',
      _RussianStrings() =>
        'Это удалит из черновика выбранные фото, место, описание и выбор кошки.',
      _ =>
        'This removes the selected photos, location, description, and cat choice from this draft.',
    };
  }

  String get delete {
    return switch (this) {
      _UzbekStrings() => 'Oʻchirish',
      _RussianStrings() => 'Удалить',
      _ => 'Delete',
    };
  }

  String get useCurrentLocationTitle {
    return switch (this) {
      _UzbekStrings() => 'Joriy joylashuv ishlatilsinmi?',
      _RussianStrings() => 'Использовать текущее местоположение?',
      _ => 'Use current location?',
    };
  }

  String get useCurrentLocationMessage {
    return switch (this) {
      _UzbekStrings() =>
        'Mushukistan joriy joylashuvingizni oʻqib, uni ushbu kuzatuvga biriktiradi. Postni joylasangiz, mushuk joylashuvi boshqa foydalanuvchilarga koʻrinishi mumkin.',
      _RussianStrings() =>
        'Mushukistan получит ваше текущее местоположение и прикрепит его к этому наблюдению. После публикации место кошки может быть видно другим пользователям.',
      _ =>
        'Mushukistan will read your current location and attach it to this observation. If you publish the post, that cat location can be visible to other users.',
    };
  }

  String get draftStatus {
    return switch (this) {
      _UzbekStrings() => 'Qoralama holati',
      _RussianStrings() => 'Статус черновика',
      _ => 'Draft status',
    };
  }

  String get photo {
    return switch (this) {
      _UzbekStrings() => 'Rasm',
      _RussianStrings() => 'Фото',
      _ => 'Photo',
    };
  }

  String get selected {
    return switch (this) {
      _UzbekStrings() => 'Tanlangan',
      _RussianStrings() => 'Выбрано',
      _ => 'Selected',
    };
  }

  String get missing {
    return switch (this) {
      _UzbekStrings() => 'Yetishmayapti',
      _RussianStrings() => 'Не указано',
      _ => 'Missing',
    };
  }

  String get location {
    return switch (this) {
      _UzbekStrings() => 'Joylashuv',
      _RussianStrings() => 'Местоположение',
      _ => 'Location',
    };
  }

  String get set {
    return switch (this) {
      _UzbekStrings() => 'Belgilangan',
      _RussianStrings() => 'Указано',
      _ => 'Set',
    };
  }

  String get catChoice {
    return switch (this) {
      _UzbekStrings() => 'Mushuk tanlovi',
      _RussianStrings() => 'Выбор кошки',
      _ => 'Cat choice',
    };
  }

  String get newCat {
    return switch (this) {
      _UzbekStrings() => 'Yangi mushuk',
      _RussianStrings() => 'Новая кошка',
      _ => 'New cat',
    };
  }

  String get existingCat {
    return switch (this) {
      _UzbekStrings() => 'Mavjud mushuk',
      _RussianStrings() => 'Существующая кошка',
      _ => 'Existing cat',
    };
  }

  String get visibility {
    return switch (this) {
      _UzbekStrings() => 'Koʻrinish',
      _RussianStrings() => 'Видимость',
      _ => 'Visibility',
    };
  }

  String get public {
    return switch (this) {
      _UzbekStrings() => 'Ochiq',
      _RussianStrings() => 'Публично',
      _ => 'Public',
    };
  }

  String get private {
    return switch (this) {
      _UzbekStrings() => 'Yopiq',
      _RussianStrings() => 'Приватно',
      _ => 'Private',
    };
  }

  String get choosePhotoFirst {
    return switch (this) {
      _UzbekStrings() => 'Avval rasm tanlang.',
      _RussianStrings() => 'Сначала выберите фото.',
      _ => 'Choose a photo first.',
    };
  }

  String get observationLocation {
    return switch (this) {
      _UzbekStrings() => 'Kuzatuv joylashuvi',
      _RussianStrings() => 'Место наблюдения',
      _ => 'Observation location',
    };
  }

  String get backToAdd {
    return switch (this) {
      _UzbekStrings() => 'Qoʻshishga qaytish',
      _RussianStrings() => 'Назад к добавлению',
      _ => 'Back to Add',
    };
  }

  String get attachLocationQuestion {
    return switch (this) {
      _UzbekStrings() => 'Joylashuv biriktirilsinmi?',
      _RussianStrings() => 'Прикрепить место?',
      _ => 'Attach a location?',
    };
  }

  String get attachLocationHelp {
    return switch (this) {
      _UzbekStrings() =>
        'Joylashuv kuzatuvni xaritada koʻrsatadi. Rasm eski boʻlsa yoki joy aniq boʻlmasa, oʻtkazib yuboring.',
      _RussianStrings() =>
        'Место делает наблюдение видимым на карте. Пропустите его, если фото старое или место неизвестно.',
      _ =>
        'A location makes the observation visible on the map. Skip it if the photo is old or the place is uncertain.',
    };
  }

  String get useMyCurrentLocation {
    return switch (this) {
      _UzbekStrings() => 'Joriy joylashuvimdan foydalanish',
      _RussianStrings() => 'Использовать мое местоположение',
      _ => 'Use my current location',
    };
  }

  String get markOnMap {
    return switch (this) {
      _UzbekStrings() => 'Xaritada belgilash',
      _RussianStrings() => 'Отметить на карте',
      _ => 'Mark on map',
    };
  }

  String get continueWithoutLocation {
    return switch (this) {
      _UzbekStrings() => 'Joylashuvsiz davom etish',
      _RussianStrings() => 'Продолжить без места',
      _ => 'Continue without location',
    };
  }

  String get couldNotResolveYourLocation {
    return switch (this) {
      _UzbekStrings() => 'Joylashuvingizni aniqlab boʻlmadi.',
      _RussianStrings() => 'Не удалось определить ваше местоположение.',
      _ => 'Could not resolve your location.',
    };
  }

  String get useThisLocation {
    return switch (this) {
      _UzbekStrings() => 'Shu joylashuvdan foydalanish',
      _RussianStrings() => 'Использовать это место',
      _ => 'Use this location',
    };
  }

  String get locatedObservation {
    return switch (this) {
      _UzbekStrings() => 'Joylashuvli kuzatuv',
      _RussianStrings() => 'Наблюдение с местом',
      _ => 'Located observation',
    };
  }

  String get feedOnlyPost {
    return switch (this) {
      _UzbekStrings() => 'Faqat lentadagi post',
      _RussianStrings() => 'Пост только в ленте',
      _ => 'Feed-only post',
    };
  }

  String get changeLocation {
    return switch (this) {
      _UzbekStrings() => 'Joylashuvni oʻzgartirish',
      _RussianStrings() => 'Изменить место',
      _ => 'Change location',
    };
  }

  String get addLocation {
    return switch (this) {
      _UzbekStrings() => 'Joylashuv qoʻshish',
      _RussianStrings() => 'Добавить место',
      _ => 'Add location',
    };
  }

  String get matchCatAndAddDetails {
    return switch (this) {
      _UzbekStrings() => 'Mushukni moslang va tafsilot qoʻshing',
      _RussianStrings() => 'Сопоставьте кошку и добавьте детали',
      _ => 'Match the cat and add details',
    };
  }

  String get feedOnlyObservationHelp {
    return switch (this) {
      _UzbekStrings() =>
        'Bu galereya kuzatuvi faqat lentada chiqadi va xaritada marker yaratmaydi.',
      _RussianStrings() =>
        'Это наблюдение из галереи появится только в ленте и не создаст маркер на карте.',
      _ =>
        'This gallery observation will appear in the feed only and will not create a map marker.',
    };
  }

  String get descriptionHint {
    return switch (this) {
      _UzbekStrings() =>
        'Mushuk, joylashuv va kerak boʻlishi mumkin boʻlgan yordamni tasvirlang',
      _RussianStrings() =>
        'Опишите кошку, место и помощь, которая может понадобиться',
      _ => 'Describe the cat, location, and any help it may need',
    };
  }

  String get newCatNameOptional {
    return switch (this) {
      _UzbekStrings() => 'Yangi mushuk nomi (ixtiyoriy)',
      _RussianStrings() => 'Имя новой кошки (необязательно)',
      _ => 'New cat name (optional)',
    };
  }

  String get unknown {
    return switch (this) {
      _UzbekStrings() => 'Nomaʼlum',
      _RussianStrings() => 'Неизвестно',
      _ => 'Unknown',
    };
  }

  String get healthy {
    return switch (this) {
      _UzbekStrings() => 'Sogʻlom',
      _RussianStrings() => 'Здорова',
      _ => 'Healthy',
    };
  }

  String get catStatus {
    return switch (this) {
      _UzbekStrings() => 'Mushuk holati',
      _RussianStrings() => 'Состояние кошки',
      _ => 'Cat status',
    };
  }

  String get publishObservation {
    return switch (this) {
      _UzbekStrings() => 'Kuzatuvni joylash',
      _RussianStrings() => 'Опубликовать наблюдение',
      _ => 'Publish observation',
    };
  }

  String get nearbyCats {
    return switch (this) {
      _UzbekStrings() => 'Yaqindagi mushuklar',
      _RussianStrings() => 'Кошки рядом',
      _ => 'Nearby cats',
    };
  }

  String get noNearbyCatsFound {
    return switch (this) {
      _UzbekStrings() => 'Yaqinda mushuk topilmadi.',
      _RussianStrings() => 'Кошек рядом не найдено.',
      _ => 'No nearby cats found.',
    };
  }

  String get thisIsNewCat {
    return switch (this) {
      _UzbekStrings() => 'Bu yangi mushuk',
      _RussianStrings() => 'Это новая кошка',
      _ => 'This is a new cat',
    };
  }

  String get published {
    return switch (this) {
      _UzbekStrings() => 'Joylandi',
      _RussianStrings() => 'Опубликовано',
      _ => 'Published',
    };
  }

  String get observationPublished {
    return switch (this) {
      _UzbekStrings() => 'Kuzatuv joylandi.',
      _RussianStrings() => 'Наблюдение опубликовано.',
      _ => 'Observation published.',
    };
  }

  String postNowAvailable(String id) {
    return switch (this) {
      _UzbekStrings() => '$id posti endi lentada mavjud.',
      _RussianStrings() => 'Пост $id теперь доступен в ленте.',
      _ => 'Post $id is now available in the feed.',
    };
  }

  String get observationSentToBackend {
    return switch (this) {
      _UzbekStrings() => 'Kuzatuvingiz backendga yuborildi.',
      _RussianStrings() => 'Ваше наблюдение отправлено на backend.',
      _ => 'Your observation has been sent to the backend.',
    };
  }

  String get viewFeed {
    return switch (this) {
      _UzbekStrings() => 'Lentani koʻrish',
      _RussianStrings() => 'Открыть ленту',
      _ => 'View feed',
    };
  }

  String get addAnother {
    return switch (this) {
      _UzbekStrings() => 'Yana qoʻshish',
      _RussianStrings() => 'Добавить еще',
      _ => 'Add another',
    };
  }

  String addPhotosCount(int count) {
    return switch (this) {
      _UzbekStrings() => 'Rasm qoʻshish ($count/5)',
      _RussianStrings() => 'Добавить фото ($count/5)',
      _ => 'Add photos ($count/5)',
    };
  }

  String get rehoming {
    return switch (this) {
      _UzbekStrings() => 'Uy topish',
      _RussianStrings() => 'Пристройство',
      _ => 'Rehoming',
    };
  }

  String get createRehomingPost {
    return switch (this) {
      _UzbekStrings() => 'Uy topish postini yaratish',
      _RussianStrings() => 'Создать пост о пристройстве',
      _ => 'Create a rehoming post',
    };
  }

  String get createRehomingPostHelp {
    return switch (this) {
      _UzbekStrings() =>
        'Mushuk va unga qanday uy kerakligini tasvirlang. Bu yoʻqolgan jonivor eʼlonlaridan alohida va xarita joylashuvini talab qilmaydi.',
      _RussianStrings() =>
        'Опишите кошку и какой дом ей нужен. Это отдельно от объявлений о потерянных питомцах и не требует места на карте.',
      _ =>
        'Describe the cat and the kind of home they need. This is separate from lost-pet alerts and does not require a map location.',
    };
  }

  String get petName {
    return switch (this) {
      _UzbekStrings() => 'Jonivor nomi',
      _RussianStrings() => 'Имя питомца',
      _ => "Pet's name",
    };
  }

  String get petNameRequired {
    return switch (this) {
      _UzbekStrings() => 'Jonivor nomini kiriting.',
      _RussianStrings() => 'Введите имя питомца.',
      _ => "Enter the pet's name.",
    };
  }

  String get additionalInformation {
    return switch (this) {
      _UzbekStrings() => 'Qoʻshimcha maʼlumot',
      _RussianStrings() => 'Дополнительная информация',
      _ => 'Additional information',
    };
  }

  String get adoptionInfoHint {
    return switch (this) {
      _UzbekStrings() => 'Yoshi, xarakteri, salomatligi va qanday uy maʼqul.',
      _RussianStrings() =>
        'Возраст, характер, здоровье и предпочтительный дом.',
      _ => 'Age, personality, health notes, and preferred home.',
    };
  }

  String get showPhonePublicly {
    return switch (this) {
      _UzbekStrings() => 'Telefon raqamim ochiq koʻrsatilsin',
      _RussianStrings() => 'Показывать мой номер телефона публично',
      _ => 'Show my phone number publicly',
    };
  }

  String get adoptionPhoneHelp {
    return switch (this) {
      _UzbekStrings() =>
        'Odamlar asrab olish haqida bogʻlanishi uchun profilingizdagi telefon raqami kerak.',
      _RussianStrings() =>
        'Людям нужен телефон из вашего профиля, чтобы связаться по поводу пристройства.',
      _ =>
        'People need your profile phone number to contact you about adoption.',
    };
  }

  String get addAtLeastOnePhoto {
    return switch (this) {
      _UzbekStrings() => 'Kamida bitta rasm qoʻshing.',
      _RussianStrings() => 'Добавьте хотя бы одно фото.',
      _ => 'Add at least one photo.',
    };
  }

  String get confirmPhonePublic {
    return switch (this) {
      _UzbekStrings() => 'Telefon raqamingiz ochiq koʻrsatilishini tasdiqlang.',
      _RussianStrings() =>
        'Подтвердите, что ваш номер телефона можно показать публично.',
      _ => 'Confirm that your phone number may be shown publicly.',
    };
  }

  String get publishAdoptionPost {
    return switch (this) {
      _UzbekStrings() => 'Asrab olish postini joylash',
      _RussianStrings() => 'Опубликовать пост о пристройстве',
      _ => 'Publish adoption post',
    };
  }

  String get adoption {
    return switch (this) {
      _UzbekStrings() => 'Asrab olish',
      _RussianStrings() => 'Пристройство',
      _ => 'Adoption',
    };
  }

  String get addComment {
    return switch (this) {
      _UzbekStrings() => 'Izoh qoʻshish',
      _RussianStrings() => 'Добавить комментарий',
      _ => 'Add a comment',
    };
  }

  String get postComment {
    return switch (this) {
      _UzbekStrings() => 'Izohni joylash',
      _RussianStrings() => 'Опубликовать комментарий',
      _ => 'Post comment',
    };
  }

  String get reply {
    return switch (this) {
      _UzbekStrings() => 'Javob berish',
      _RussianStrings() => 'Ответить',
      _ => 'Reply',
    };
  }

  String get replyingTo {
    return switch (this) {
      _UzbekStrings() => 'Javob:',
      _RussianStrings() => 'Ответ пользователю:',
      _ => 'Replying to',
    };
  }

  String get cancelReply {
    return switch (this) {
      _UzbekStrings() => 'Javobni bekor qilish',
      _RussianStrings() => 'Отменить ответ',
      _ => 'Cancel reply',
    };
  }

  String get readMore {
    return switch (this) {
      _UzbekStrings() => 'Batafsil',
      _RussianStrings() => 'Читать далее',
      _ => 'Read more',
    };
  }

  String get showLess {
    return switch (this) {
      _UzbekStrings() => 'Kamroq ko‘rsatish',
      _RussianStrings() => 'Свернуть',
      _ => 'Show less',
    };
  }

  String get hide {
    return switch (this) {
      _UzbekStrings() => 'Yashirish',
      _RussianStrings() => 'Скрыть',
      _ => 'Hide',
    };
  }

  String get noPublicPostFoundForCat {
    return switch (this) {
      _UzbekStrings() => 'Bu mushuk uchun ochiq post topilmadi.',
      _RussianStrings() => 'Публичный пост для этой кошки не найден.',
      _ => 'No public post found for this cat.',
    };
  }

  String couldNotOpenPost(Object error) {
    return switch (this) {
      _UzbekStrings() => 'Postni ochib boʻlmadi: $error',
      _RussianStrings() => 'Не удалось открыть пост: $error',
      _ => 'Could not open post: $error',
    };
  }

  String get useMyLocation {
    return switch (this) {
      _UzbekStrings() => 'Joylashuvimdan foydalanish',
      _RussianStrings() => 'Использовать мое место',
      _ => 'Use my location',
    };
  }

  String get observation {
    return switch (this) {
      _UzbekStrings() => 'Kuzatuv',
      _RussianStrings() => 'Наблюдение',
      _ => 'Observation',
    };
  }

  String get report {
    return switch (this) {
      _UzbekStrings() => 'Shikoyat qilish',
      _RussianStrings() => 'Пожаловаться',
      _ => 'Report',
    };
  }

  String get reportTargetUnavailable {
    return switch (this) {
      _UzbekStrings() => 'Shikoyat qilish uchun kontentni tanlang.',
      _RussianStrings() => 'Выберите контент для жалобы.',
      _ => 'Choose content to report.',
    };
  }

  String get reportTargetSummary {
    return switch (this) {
      _UzbekStrings() => 'Tanlangan kontent haqida shikoyat qilyapsiz.',
      _RussianStrings() => 'Вы жалуетесь на выбранный контент.',
      _ => 'You are reporting the selected content.',
    };
  }

  String get couldNotSubmitReport {
    return switch (this) {
      _UzbekStrings() => 'Shikoyatni yuborib bo‘lmadi. Qayta urinib ko‘ring.',
      _RussianStrings() => 'Не удалось отправить жалобу. Повторите попытку.',
      _ => 'Could not submit the report. Please try again.',
    };
  }

  String get couldNotLoadProfile {
    return switch (this) {
      _UzbekStrings() => 'Profilni yuklab bo‘lmadi. Qayta urinib ko‘ring.',
      _RussianStrings() => 'Не удалось загрузить профиль. Повторите попытку.',
      _ => 'Could not load your profile. Please try again.',
    };
  }

  String get locationOutsideMap {
    return switch (this) {
      _UzbekStrings() => 'Joylashuvingiz Toshkent xaritasi hududidan tashqarida.',
      _RussianStrings() => 'Ваше местоположение находится за пределами карты Ташкента.',
      _ => 'Your location is outside the Tashkent map area.',
    };
  }

  String get changeProfilePicture {
    return switch (this) {
      _UzbekStrings() => 'Profil rasmini oʻzgartirish',
      _RussianStrings() => 'Изменить фото профиля',
      _ => 'Change profile picture',
    };
  }

  String get useCamera {
    return switch (this) {
      _UzbekStrings() => 'Kameradan foydalanish',
      _RussianStrings() => 'Использовать камеру',
      _ => 'Use camera',
    };
  }

  String get telegramUsername {
    return switch (this) {
      _UzbekStrings() => 'Telegram username',
      _RussianStrings() => 'Имя пользователя Telegram',
      _ => 'Telegram username',
    };
  }

  String get bio {
    return switch (this) {
      _UzbekStrings() => 'Bio',
      _RussianStrings() => 'О себе',
      _ => 'Bio',
    };
  }

  String get bioHint {
    return switch (this) {
      _UzbekStrings() => 'Toshkentdan Aydos, mushuklarni yaxshi koʻradi',
      _RussianStrings() => 'Айдос из Ташкента, любит кошек',
      _ => 'Aydos from Tashkent, cat lover',
    };
  }

  String get uzbekPhoneFormatHelp {
    return switch (this) {
      _UzbekStrings() => 'Oʻzbekiston formati: +998 xx xxx xx xx',
      _RussianStrings() => 'Формат Узбекистана: +998 xx xxx xx xx',
      _ => 'Uzbekistan format: +998 xx xxx xx xx',
    };
  }

  String get telegramValidation {
    return switch (this) {
      _UzbekStrings() =>
        '5-32 ta harf, raqam yoki pastki chiziqdan foydalaning.',
      _RussianStrings() =>
        'Используйте 5-32 буквы, цифры или нижние подчеркивания.',
      _ => 'Use 5-32 letters, numbers, or underscores.',
    };
  }

  String get profileNotFound {
    return switch (this) {
      _UzbekStrings() => 'Profil topilmadi.',
      _RussianStrings() => 'Профиль не найден.',
      _ => 'Profile not found.',
    };
  }

  String get blockUser {
    return switch (this) {
      _UzbekStrings() => 'Foydalanuvchini bloklash',
      _RussianStrings() => 'Заблокировать пользователя',
      _ => 'Block user',
    };
  }

  String get userBlocked {
    return switch (this) {
      _UzbekStrings() => 'Foydalanuvchi bloklandi.',
      _RussianStrings() => 'Пользователь заблокирован.',
      _ => 'User blocked.',
    };
  }

  String get blockUserTitle {
    return switch (this) {
      _UzbekStrings() => 'Foydalanuvchi bloklansinmi?',
      _RussianStrings() => 'Заблокировать пользователя?',
      _ => 'Block user?',
    };
  }

  String get blockUserMessage {
    return switch (this) {
      _UzbekStrings() =>
        'Foydalanuvchi haqoratli yoki xavfli boʻlsa, shundan foydalaning. Blokdan chiqarish interfeysi qoʻshilguncha supportdan yordam soʻrashingiz mumkin.',
      _RussianStrings() =>
        'Используйте это, если пользователь ведет себя оскорбительно или небезопасно. Пока интерфейс разблокировки не добавлен, можно попросить support разблокировать пользователя.',
      _ =>
        'Use this when a user is abusive or unsafe. You can ask support to unblock them until the unblock UI is added.',
    };
  }

  String get block {
    return switch (this) {
      _UzbekStrings() => 'Bloklash',
      _RussianStrings() => 'Заблокировать',
      _ => 'Block',
    };
  }

  String get englishLanguage {
    return switch (this) {
      _UzbekStrings() => 'Inglizcha',
      _RussianStrings() => 'Английский',
      _ => 'English',
    };
  }

  String get uzbekLanguage {
    return switch (this) {
      _UzbekStrings() => 'Oʻzbekcha',
      _RussianStrings() => 'Узбекский',
      _ => 'Uzbek',
    };
  }

  String get russianLanguage {
    return switch (this) {
      _UzbekStrings() => 'Ruscha',
      _RussianStrings() => 'Русский',
      _ => 'Russian',
    };
  }

  String get confirmingEmail {
    return switch (this) {
      _UzbekStrings() => 'Email tasdiqlanmoqda...',
      _RussianStrings() => 'Email подтверждается...',
      _ => 'Confirming your email...',
    };
  }

  String get emailVerifiedSignInNow {
    return switch (this) {
      _UzbekStrings() => 'Email tasdiqlandi. Endi kirishingiz mumkin.',
      _RussianStrings() => 'Email подтвержден. Теперь можно войти.',
      _ => 'Email verified. You can sign in now.',
    };
  }

  String get couldNotVerifyEmailLink {
    return switch (this) {
      _UzbekStrings() => 'Bu email havolasini tasdiqlab boʻlmadi.',
      _RussianStrings() => 'Не удалось подтвердить эту ссылку email.',
      _ => 'Could not verify this email link.',
    };
  }

  String get googleSignInNoIdToken {
    return switch (this) {
      _UzbekStrings() => 'Google kirishi ID token qaytarmadi.',
      _RussianStrings() => 'Вход через Google не вернул ID token.',
      _ => 'Google sign-in did not return an ID token.',
    };
  }

  String get googleSignInFailed {
    return switch (this) {
      _UzbekStrings() => 'Google orqali kirish amalga oshmadi.',
      _RussianStrings() => 'Не удалось войти через Google.',
      _ => 'Google sign-in failed.',
    };
  }

  String get googleSignInNotConfigured {
    return switch (this) {
      _UzbekStrings() => 'Bu build uchun Google orqali kirish sozlanmagan.',
      _RussianStrings() => 'Вход через Google не настроен для этой сборки.',
      _ => 'Google sign-in is not configured for this build.',
    };
  }

  String get googleSignInUnavailable {
    return switch (this) {
      _UzbekStrings() => 'Google orqali kirish hozir mavjud emas.',
      _RussianStrings() => 'Вход через Google сейчас недоступен.',
      _ => 'Google sign-in is unavailable.',
    };
  }

  String get landOfCats {
    return switch (this) {
      _UzbekStrings() => 'Mushuklar yurti',
      _RussianStrings() => 'Страна кошек',
      _ => 'The land of cats',
    };
  }

  String get everythingCatsTitle {
    return switch (this) {
      _UzbekStrings() => 'Mushuklarga oid hammasi bir sokin joyda',
      _RussianStrings() => 'Все о кошках в одном спокойном месте',
      _ => 'Everything cats in one calm place',
    };
  }

  String get everythingCatsMessage {
    return switch (this) {
      _UzbekStrings() =>
        'Kuzatuvlarni ulashing, yordam kerak mushuklarni belgilang, yoʻqolgan jonivorlarni qidiring, mushuklarga yangi uy toping va yaqin foydali joylarni toping.',
      _RussianStrings() =>
        'Делитесь наблюдениями, отмечайте кошек, которым нужна помощь, ищите потерянных питомцев, пристраивайте кошек и находите полезные места рядом.',
      _ =>
        'Share sightings, tag observations as Needs help for cats in need, search for lost pets, rehome cats, and discover useful places nearby.',
    };
  }

  String get urgentAlerts {
    return switch (this) {
      _UzbekStrings() => 'Shoshilinch eʼlonlar',
      _RussianStrings() => 'Срочные объявления',
      _ => 'Urgent alerts',
    };
  }

  String get newHomes {
    return switch (this) {
      _UzbekStrings() => 'Yangi uylar',
      _RussianStrings() => 'Новые дома',
      _ => 'New homes',
    };
  }

  String get adoptionPosts {
    return switch (this) {
      _UzbekStrings() => 'Asrab olish postlari',
      _RussianStrings() => 'Посты о пристройстве',
      _ => 'Adoption posts',
    };
  }

  String get usefulPlaces {
    return switch (this) {
      _UzbekStrings() => 'Foydali joylar',
      _RussianStrings() => 'Полезные места',
      _ => 'Useful places',
    };
  }

  String get vetsShopsShelters {
    return switch (this) {
      _UzbekStrings() => 'Veterinarlar, doʻkonlar, shelterlar',
      _RussianStrings() => 'Ветклиники, магазины, приюты',
      _ => 'Vets, shops, shelters',
    };
  }

  String get nearbyMap {
    return switch (this) {
      _UzbekStrings() => 'Yaqin xarita',
      _RussianStrings() => 'Карта рядом',
      _ => 'Nearby map',
    };
  }

  String get catsAndServices {
    return switch (this) {
      _UzbekStrings() => 'Mushuklar va xizmatlar',
      _RussianStrings() => 'Кошки и сервисы',
      _ => 'Cats and services',
    };
  }

  String get useYourLocation {
    return switch (this) {
      _UzbekStrings() => 'Joylashuvingizdan foydalanish',
      _RussianStrings() => 'Использовать ваше местоположение',
      _ => 'Use your location',
    };
  }

  String get locationDisclosureMessage {
    return switch (this) {
      _UzbekStrings() =>
        'Mushukistan yaqin mushuklar va foydali joylarni koʻrsatish uchun joriy joylashuvingizdan foydalanadi. Ochiq post yaratmasangiz, u joylanmaydi.',
      _RussianStrings() =>
        'Mushukistan использует ваше текущее местоположение, чтобы показывать кошек и полезные места рядом. Оно не публикуется, если вы не создадите публичный пост.',
      _ =>
        'Mushukistan uses your current location to show nearby cats and useful places. It is not published unless you create a public post.',
    };
  }

  String get feedStatus {
    return switch (this) {
      _UzbekStrings() => 'Lenta',
      _RussianStrings() => 'Лента',
      _ => 'Feed',
    };
  }

  String get moderationReports {
    return switch (this) {
      _UzbekStrings() => 'Moderatsiya shikoyatlari',
      _RussianStrings() => 'Жалобы модерации',
      _ => 'Moderation reports',
    };
  }

  String get noOpenReports {
    return switch (this) {
      _UzbekStrings() => 'Ochiq shikoyatlar yoʻq.',
      _RussianStrings() => 'Открытых жалоб нет.',
      _ => 'No open reports.',
    };
  }

  String get noReasonProvided {
    return switch (this) {
      _UzbekStrings() => 'Sabab kiritilmagan.',
      _RussianStrings() => 'Причина не указана.',
      _ => 'No reason provided.',
    };
  }

  String get reportDetail {
    return switch (this) {
      _UzbekStrings() => 'Shikoyat tafsiloti',
      _RussianStrings() => 'Детали жалобы',
      _ => 'Report detail',
    };
  }

  String get reportUnavailable {
    return switch (this) {
      _UzbekStrings() => 'Bu shikoyat endi mavjud emas.',
      _RussianStrings() => 'Эта жалоба больше недоступна.',
      _ => 'This report is no longer available.',
    };
  }

  String get couldNotLoadReports {
    return switch (this) {
      _UzbekStrings() => 'Shikoyatlarni yuklab bo‘lmadi.',
      _RussianStrings() => 'Не удалось загрузить жалобы.',
      _ => 'Could not load reports.',
    };
  }

  String get backToReports {
    return switch (this) {
      _UzbekStrings() => 'Shikoyatlarga qaytish',
      _RussianStrings() => 'К жалобам',
      _ => 'Back to reports',
    };
  }

  String targetId(String id) {
    return switch (this) {
      _UzbekStrings() => 'Nishon ID: $id',
      _RussianStrings() => 'ID объекта: $id',
      _ => 'Target ID: $id',
    };
  }

  String targetTitle(String title) {
    return switch (this) {
      _UzbekStrings() => 'Sarlavha: $title',
      _RussianStrings() => 'Заголовок: $title',
      _ => 'Title: $title',
    };
  }

  String targetStatus(String status) {
    return switch (this) {
      _UzbekStrings() => 'Holat: $status',
      _RussianStrings() => 'Статус: $status',
      _ => 'Status: $status',
    };
  }

  String get resolve {
    return switch (this) {
      _UzbekStrings() => 'Hal qilish',
      _RussianStrings() => 'Решить',
      _ => 'Resolve',
    };
  }

  String get dismiss {
    return switch (this) {
      _UzbekStrings() => 'Rad etish',
      _RussianStrings() => 'Отклонить',
      _ => 'Dismiss',
    };
  }

  String get reportStatus {
    return switch (this) {
      _UzbekStrings() => 'Shikoyat holati',
      _RussianStrings() => 'Статус жалобы',
      _ => 'Report status',
    };
  }

  String get noAction {
    return switch (this) {
      _UzbekStrings() => 'Amal yoʻq',
      _RussianStrings() => 'Без действия',
      _ => 'No action',
    };
  }

  String get softDeletePost {
    return switch (this) {
      _UzbekStrings() => 'Postni yashirib oʻchirish',
      _RussianStrings() => 'Мягко удалить пост',
      _ => 'Soft delete post',
    };
  }

  String get softDeleteComment {
    return switch (this) {
      _UzbekStrings() => 'Izohni yashirib oʻchirish',
      _RussianStrings() => 'Мягко удалить комментарий',
      _ => 'Soft delete comment',
    };
  }

  String get suspendUser {
    return switch (this) {
      _UzbekStrings() => 'Foydalanuvchini toʻxtatish',
      _RussianStrings() => 'Заблокировать пользователя',
      _ => 'Suspend user',
    };
  }

  String get moderationAction {
    return switch (this) {
      _UzbekStrings() => 'Moderatsiya amali',
      _RussianStrings() => 'Действие модерации',
      _ => 'Moderation action',
    };
  }

  String get note {
    return switch (this) {
      _UzbekStrings() => 'Eslatma',
      _RussianStrings() => 'Заметка',
      _ => 'Note',
    };
  }

  String get saveModerationDecision {
    return switch (this) {
      _UzbekStrings() => 'Moderatsiya qarorini saqlash',
      _RussianStrings() => 'Сохранить решение модерации',
      _ => 'Save moderation decision',
    };
  }

  String get reportContent {
    return switch (this) {
      _UzbekStrings() => 'Kontentdan shikoyat qilish',
      _RussianStrings() => 'Пожаловаться на контент',
      _ => 'Report content',
    };
  }

  String get post {
    return switch (this) {
      _UzbekStrings() => 'Post',
      _RussianStrings() => 'Пост',
      _ => 'Post',
    };
  }

  String get comment {
    return switch (this) {
      _UzbekStrings() => 'Izoh',
      _RussianStrings() => 'Комментарий',
      _ => 'Comment',
    };
  }

  String get user {
    return switch (this) {
      _UzbekStrings() => 'Foydalanuvchi',
      _RussianStrings() => 'Пользователь',
      _ => 'User',
    };
  }

  String get cat {
    return switch (this) {
      _UzbekStrings() => 'Mushuk',
      _RussianStrings() => 'Кошка',
      _ => 'Cat',
    };
  }

  String get targetType {
    return switch (this) {
      _UzbekStrings() => 'Nishon turi',
      _RussianStrings() => 'Тип объекта',
      _ => 'Target type',
    };
  }

  String get targetIdLabel {
    return switch (this) {
      _UzbekStrings() => 'Nishon ID',
      _RussianStrings() => 'ID объекта',
      _ => 'Target ID',
    };
  }

  String get targetIdRequired {
    return switch (this) {
      _UzbekStrings() => 'Nishon ID kiritilishi kerak.',
      _RussianStrings() => 'Укажите ID объекта.',
      _ => 'Target ID is required.',
    };
  }

  String get reason {
    return switch (this) {
      _UzbekStrings() => 'Sabab',
      _RussianStrings() => 'Причина',
      _ => 'Reason',
    };
  }

  String get reasonRequired {
    return switch (this) {
      _UzbekStrings() => 'Iltimos, sababni kiriting.',
      _RussianStrings() => 'Пожалуйста, укажите причину.',
      _ => 'Please provide a reason.',
    };
  }

  String get childSafetyReportReason {
    return switch (this) {
      _UzbekStrings() => 'Bolalar xavfsizligi / ekspluatatsiya',
      _RussianStrings() => 'Безопасность детей / эксплуатация',
      _ => 'Child safety / exploitation',
    };
  }

  String get inappropriateContentReportReason {
    return switch (this) {
      _UzbekStrings() => 'Nomaqbul kontent',
      _RussianStrings() => 'Неприемлемый контент',
      _ => 'Inappropriate content',
    };
  }

  String get harassmentReportReason {
    return switch (this) {
      _UzbekStrings() => 'Tazyiq yoki haqorat',
      _RussianStrings() => 'Травля или оскорбления',
      _ => 'Harassment or abuse',
    };
  }

  String get spamReportReason {
    return switch (this) {
      _UzbekStrings() => 'Spam',
      _RussianStrings() => 'Спам',
      _ => 'Spam',
    };
  }

  String get otherReportReason {
    return switch (this) {
      _UzbekStrings() => 'Boshqa',
      _RussianStrings() => 'Другое',
      _ => 'Other',
    };
  }

  String get reportDetails {
    return switch (this) {
      _UzbekStrings() => 'Tafsilotlar',
      _RussianStrings() => 'Подробности',
      _ => 'Details',
    };
  }

  String get reportSubmitted {
    return switch (this) {
      _UzbekStrings() => 'Shikoyat yuborildi.',
      _RussianStrings() => 'Жалоба отправлена.',
      _ => 'Report submitted.',
    };
  }

  String get submitReport {
    return switch (this) {
      _UzbekStrings() => 'Shikoyatni yuborish',
      _RussianStrings() => 'Отправить жалобу',
      _ => 'Submit report',
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

  String get publishLostPet {
    return switch (this) {
      _UzbekStrings() => 'Yo‘qolgan jonivorni joylash',
      _RussianStrings() => 'Опубликовать потерянного питомца',
      _ => 'Publish lost pet',
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
          nameOptional: 'Name',
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
          nameOptional: 'Ism',
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
          nameOptional: 'Имя',
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
