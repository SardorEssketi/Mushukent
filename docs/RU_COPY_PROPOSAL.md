# Russian UI copy: proposed changes

Status: **proposal, not applied** (2026-11-25). Follows `docs/RU_STYLE_GUIDE.md`. Only strings that
need a change are listed. Out of scope: legal documents and their in-app summaries
(`privacyPolicySummary`, `termsOfServiceSummary`, `accountDeletionSummary`, `legalUpdateBody`), the
contact notice from 731d594 (`contactNoticePhone`, `contactNoticePhoneAndTelegram`) and
developer-only text (`devVerificationHelp`).

Files: `app_strings.dart` unless noted; `notif` = `notification_strings.dart`, `feedback` =
`feedback_strings.dart`, `security` = `account_security_strings.dart`, `help` =
`adoption_help_screen.dart`.

Two items are content fixes, not just style (marked **fix**): `createLostPetAlertHelp` still asks
for the consent removed in 731d594 (English and Uzbek need the same fix), and moderation texts
use «обжалованный» ("appealed") where they mean "reported".

## 1. Profile and settings
| Key | Current | Proposed | Reason |
|---|---|---|---|
| yourActivities | Ваши активности | Ваши посты и объявления | «активности» (plural) is a calque; names what the screen holds |
| resourcesAndAccount | Полезное и аккаунт | Полезное и настройки | the section holds help, settings and feedback |
| profileActions | Действия с профилем | Меню профиля | officialese |
| postActions | Действия с публикацией | Меню поста | officialese; glossary «пост» |
| recentObservations | Недавние публикации | Последние посты | glossary |
| discardChanges | Отменить изменения | Не сохранять | button answers «Выйти без сохранения?» |
| keepEditing | Продолжить редактирование | Остаться | short verb |
| editObservation | Редактировать публикацию | Изменить пост | shorter; glossary |
| deletePost | Удалить публикацию | Удалить пост | glossary |
| postHistory | История публикации | История изменений | says what it is |
| viewPostHistory | История публикации | История изменений | same |
| moderatorOnlyHistory | История публикации доступна только модераторам. | Историю изменений видят только модераторы. | active voice |
| invalidUzbekPhone | Используйте формат телефона Узбекистана: +998 XX XXX XXXX. | Введите номер в формате +998 XX XXX XX XX. | plain; grouping matches the hint |
| uzbekPhoneFormatHelp | Формат Узбекистана: +998 xx xxx xx xx | Например: +998 90 123 45 67 | an example is clearer than a mask |
| telegramUsername | Имя пользователя Telegram | Ник в Telegram | everyday word |
| telegramValidation | Используйте 5-32 буквы, цифры или нижние подчеркивания. | От 5 до 32 символов: латинские буквы, цифры и _. | says Latin only; ё; plain |
| blockUserMessage | Вы не будете видеть публикации и комментарии этого пользователя, а он не сможет взаимодействовать с вашим контентом и отправлять вам уведомления. Разблокировать можно в Настройки > Заблокированные пользователи. | Вы перестанете видеть его посты и комментарии, а он не сможет отвечать на ваши и присылать вам уведомления. Разблокировать можно в «Настройки → Заблокированные пользователи». | shorter; quotes and arrow |
| noActivityVisible | Этот пользователь скрыл свою активность. | Пользователь скрыл свои посты и комментарии. | concrete |
| allowPublicActivityView | Разрешить другим видеть мою активность | Показывать другим мои посты и комментарии | concrete |
| confirmLogoutMessage | Чтобы продолжить пользоваться аккаунтом, нужно будет войти снова. | Чтобы вернуться, просто войдите снова. | shorter |
| themeDark | Темная | Тёмная | ё |
| couldNotSaveChanges | Не удалось сохранить изменения. | Не удалось сохранить изменения. Попробуйте ещё раз. | error says what to do |
| couldNotLoadProfile | Не удалось загрузить профиль. Повторите попытку. | Не удалось загрузить профиль. Попробуйте ещё раз. | standard retry phrase |
| donateToAuthor | Пожертвовать автору | Поддержать автора | warmer, common wording |
| confirmDeleteAccountMessage | Ваш аккаунт будет отключен, а текущая сессия завершится. Существующий контент может сохраниться для модерации. | Мы отключим аккаунт, и вы выйдете из него. Часть данных может храниться для модерации. | active voice; no «сессия»; ё |
| accountDeleted | Аккаунт удален. | Аккаунт удалён. | ё |
| couldNotDeleteAccount | Не удалось удалить аккаунт. | Не удалось удалить аккаунт. Попробуйте ещё раз. | error says what to do |
| noLeaderboardData | Данных лидерборда пока нет. | Рейтинг пока пуст. | no «лидерборд» |

## 2. Post creation (cat posts, «Кошке нужна помощь», photos, drafts, location)
| Key | Current | Proposed | Reason |
|---|---|---|---|
| createInMushukistan | Создать в Mushukistan | Новый пост | short title |
| chooseShareType | Выберите тип помощи кошке или обновления, которым хотите поделиться. | Выберите, чем хотите поделиться. | shorter |
| needsHelpLocationRequired | Для поста «Кошке нужна помощь» укажите место. | Укажите на карте, где кошка. | plain |
| needsHelpLocationHelp | Подтвердите место, чтобы люди могли найти кошку. | Укажите место, чтобы кошку могли найти. | «подтвердите» is misleading |
| preparingPhotoForUpload | Фото готовится к загрузке... | Готовим фото… | active; ellipsis |
| couldNotPreparePhoto | Не удалось подготовить фото. Выберите другое изображение JPEG или PNG. | Не получилось обработать фото. Выберите другое (JPEG или PNG). | plain |
| photoUploadTimedOut | Загрузка фото заняла слишком много времени. Проверьте подключение и повторите попытку. | Фото загружалось слишком долго. Проверьте интернет и попробуйте ещё раз. | glossary; standard retry |
| photoUploadNetworkError | Не удалось загрузить фото. Проверьте подключение и повторите попытку. | Не удалось загрузить фото. Проверьте интернет и попробуйте ещё раз. | same |
| photoUploadStorageError | Не удалось загрузить фото. Повторите попытку позже. | Не удалось загрузить фото. Попробуйте чуть позже. | standard retry |
| publicationOutcomeUnknown | Публикация могла сохраниться. Проверьте статус перед повторной отправкой. Черновик сохранён на этом экране. | Возможно, пост уже опубликован. Проверьте это, прежде чем отправлять снова. Черновик на месте. | plain; shorter |
| checkPublicationStatus | Проверить статус публикации | Проверить, опубликован ли | button says the action |
| publicationCompletedUnavailable | Публикация уже создана, но открыть её здесь нельзя. Для новой публикации начните новый черновик. | Пост уже опубликован, но открыть его отсюда нельзя. Чтобы создать новый, начните заново. | glossary; plain |
| invalidPhoto | Изображение повреждено или не читается. Выберите другое фото. | Это фото не открывается. Выберите другое. | shorter |
| photoTooLarge | Изображение слишком большое. Выберите фото меньшего размера. | Фото слишком большое. Выберите другое. | shorter |
| draftDeleted | Черновик удален. | Черновик удалён. | ё |
| draftStatus | Статус черновика | Черновик поста | it labels the draft card |
| lostPetDraftLabel | Черновик: потерянный питомец | Черновик объявления о пропаже | natural phrase |
| rehomingDraftLabel | Черновик: пристройство | Черновик объявления о пристройстве | natural phrase |
| deleteDraftMessage | Это удалит из черновика выбранные фото, место, описание и выбор кошки. | Фото, место и описание из черновика пропадут. | plain; the draft has no cat choice any more |
| deleteLostPetDraftMessage | Это удалит из черновика выбранные фото, место, где питомца видели последний раз, кличку и дополнительную информацию. | Фото, место, кличка и описание из черновика пропадут. | shorter |
| deleteRehomingDraftMessage | Это удалит из черновика выбранные фото, кличку и дополнительную информацию. | Фото, кличка и описание из черновика пропадут. | shorter |
| useCurrentLocationMessage | Mushukistan получит ваше текущее местоположение и прикрепит его к этому посту. После публикации место кошки может быть видно другим пользователям. | Мы добавим к посту ваше текущее местоположение. После публикации его увидят другие. | «мы»; shorter |
| useMyCurrentLocation | Использовать мое местоположение | Использовать моё местоположение | ё |
| publicationUnavailableTitle | Публикация недоступна | Пост недоступен | glossary |
| publicationUnavailableMessage | Возможно, она удалена или больше не видна вам. | Возможно, его удалили или скрыли. | active; follows the title |
| addAnother | Добавить еще | Добавить ещё | ё |

## 3. Lost pets
| Key | Current | Proposed | Reason |
|---|---|---|---|
| createLostPetAlertHelp | Добавьте чёткие фото, место, где питомца видели в последний раз, и согласие на показ ваших контактов, чтобы с вами могли быстро связаться. | Добавьте чёткие фото и отметьте, где питомца видели в последний раз, — так его быстрее узнают. | **fix**: the consent no longer exists (en/uz too) |
| lostPetAlertSubtitle | Сообщите о пропавшем питомце и месте, где его видели в последний раз. | Расскажите, где питомца видели в последний раз. | shorter |
| phoneNumberRequiredForLostPet | Добавьте корректный номер телефона Узбекистана перед публикацией потерянного питомца. Например: +998 99 142 1314. | Чтобы с вами могли связаться, добавьте в профиль номер Узбекистана, например +998 90 123 45 67. | reason first; neutral example |
| createLostPetAlert | Создать объявление о пропавшем питомце | Объявление о пропаже | short title |
| petsName | Имя питомца | Кличка | glossary |
| enterPetsName | Введите имя питомца. | Укажите кличку. | glossary |
| publishLostPet | Опубликовать потерянного питомца | Опубликовать объявление | «опубликовать питомца» is wrong |
| lastSeenLocationSelected | Место последнего обнаружения выбрано. | Место отмечено. | officialese |
| markLostPetFound | Отметить как найденного | Питомец нашёлся | natural; button states the fact |
| lostPetResolutionMessage | Объявление исчезнет из ленты и с карты, но останется доступным по ссылке. В профиле его можно снова открыть или удалить. | Мы уберём объявление из ленты и с карты, но по ссылке оно откроется. Вернуть или удалить его можно в профиле. | «мы»; plain |
| foundPostPrivateDetails | После того как питомец найден, номер телефона и точное место последнего обнаружения скрыты от других. | Питомец нашёлся, поэтому телефон и точное место теперь скрыты. | plain |
| myLostPets | Мои потерянные питомцы | Мои объявления о пропаже | glossary |
| editLostPet | Редактировать объявление о питомце | Изменить объявление | shorter |
| deleteLostPetMessage | Это объявление о питомце будет удалено. | Объявление удалится насовсем. | says the consequence |
| activeLostPet | Поиск продолжается | Ищут | short status |
| reunitedLostPet | Найден | Нашёлся | natural |
| noLostPetsYet | Пока нет объявлений о потерянных питомцах. | У вас пока нет объявлений о пропаже. | glossary |
| contactRevealLimit | Вы открыли максимально допустимое число контактов. Попробуйте позже. | Вы открыли много контактов за короткое время. Попробуйте позже. | officialese |

## 4. Rehoming (adoption)
| Key | Current | Proposed | Reason |
|---|---|---|---|
| phoneNumberRequiredForAdoption | Добавьте номер телефона перед созданием поста о пристройстве, чтобы люди могли связаться с вами. | Чтобы с вами могли связаться, добавьте в профиль номер телефона. | reason first; shorter |
| findANewHomeSubtitle | Помогите питомцу найти новый дом: добавьте фото и сведения о нём. | Добавьте фото и расскажите о питомце. | shorter |
| createRehomingPost | Создать пост о пристройстве | Объявление о пристройстве | title; glossary |
| createRehomingPostHelp | Опишите кошку и какой дом ей нужен. Это отдельно от объявлений о потерянных питомцах и не требует места на карте. | Расскажите о питомце и о том, какой дом ему нужен. Место на карте не нужно. | shorter; glossary |
| petName | Имя питомца | Кличка | glossary |
| petNameRequired | Введите имя питомца. | Укажите кличку. | glossary |
| additionalInformation | Дополнительная информация | Подробности | shorter (also used in lost pets) |
| adoptionInfoHint | Возраст, характер, здоровье и предпочтительный дом. | Возраст, характер, здоровье и какой дом подойдёт. | plain |
| publishAdoptionPost | Опубликовать пост о пристройстве | Опубликовать объявление | glossary; shorter |
| markRehomed | Отметить, что питомец нашёл дом | Питомец нашёл дом | short |
| adoptionResolutionMessage | Объявление исчезнет из ленты, но останется доступным по ссылке. В профиле его можно снова открыть или удалить. | Мы уберём объявление из ленты, но по ссылке оно откроется. Вернуть или удалить его можно в профиле. | «мы»; plain |
| rehomedPostPrivateDetails | После того как питомец нашёл новый дом, контактные данные скрыты от других. | Питомец уже дома, поэтому контакты теперь скрыты. | plain |
| editAdoptionPost | Редактировать объявление о пристройстве | Изменить объявление | shorter |
| deleteAdoptionPostMessage | Это объявление о пристройстве будет удалено. | Объявление удалится насовсем. | says the consequence |
| noAdoptionPostsYet | Пока нет объявлений о пристройстве. | У вас пока нет объявлений о пристройстве. | it is the user's own list |
| adoptionHelp | Помощь по усыновлению кошки | Как взять кошку домой | «усыновление» is for children |
| adoptionHelpDisclaimer | Это общая информация. По вашей ситуации уточните требования в районной/городской государственной ветеринарной службе или у юриста. | Это общая информация. Для вашего случая уточните правила в районной или городской госветслужбе или у юриста. | shorter; no slash |
| adoptionVetProcedure | Ветеринарная процедура | Визит к ветеринару | plain |
| adoptionLegalCareRules | Правила содержания дома | Как содержать кошку дома | plain |
| help: before[1] | Если кошка ранена, агрессивна или есть признаки, похожие на бешенство, не ловите ее руками; обратитесь в ветеринарную службу или службу отлова безнадзорных животных. | Если кошка ранена, агрессивна или похожа на больную бешенством, не берите её руками — позвоните в ветслужбу или службу отлова. | shorter; ё |
| help: vet[1] | Обратитесь к представителю государственной ветеринарной службы по месту постоянного или временного проживания, чтобы уточнить идентификацию и учет. | Узнайте в госветслужбе по месту жительства, как поставить кошку на учёт и чипировать её. | plain (check with the source before applying) |
| help: rules[0] | В отдельной квартире многоэтажного дома правила предусматривают содержание 1 кошки; может требоваться согласие соседей и товарищества собственников жилья. | В квартире многоэтажного дома по правилам можно держать одну кошку; может понадобиться согласие соседей и ТСЖ. | plain |

## 5. Feed, map and leaderboard
| Key | Current | Proposed | Reason |
|---|---|---|---|
| feedEmptyMessage (popular) | За этот период нет популярных публикаций. | За этот период популярных постов нет. | glossary |
| emptyFeedMessage | Поделитесь постом о кошке, объявлением о потерянном питомце или постом о пристройстве. | Здесь пока пусто. Расскажите о кошке, о пропавшем питомце или о том, кому нужен дом. | empty state says what's here |
| noMorePosts | Больше публикаций нет. | Больше постов нет. | glossary |
| newPosts | Новые публикации | Новые посты | glossary |
| busyRetryingIn | Сервис занят. Повторим через $seconds с | Сервер занят. Попробуем снова через $seconds с | plain |
| couldNotLoadSection | Не удалось загрузить этот раздел | Не удалось загрузить. Попробуйте ещё раз. | error says what to do |
| locationOutsideMap | Ваше местоположение находится за пределами карты Ташкента. | Вы за пределами карты: пока она охватывает только Ташкент. | plain; explains |
| vetPharmacies | Ветеринарные аптеки | Ветаптеки | matches the other place labels |
| feedIntroMap | Карта – кошки и места для питомцев рядом | Карта — кошки и полезные места рядом | em dash; glossary |
| feedIntroAdd | Добавить – опубликуйте кошку, которую видели | Добавить — расскажите о кошке, которую встретили | em dash; natural |
| feedIntroLostPets | Потерянные питомцы – помогите им вернуться домой | Потерянные питомцы — помогите им вернуться домой | em dash |
| feedIntroAdoption | Пристройство – найдите дом или подарите его | Пристройство — найдите питомцу дом или возьмите питомца к себе | em dash; «подарить дом» is unclear |

## 6. Comments and notifications
| Key | Current | Proposed | Reason |
|---|---|---|---|
| couldNotLoadMoreComments | Не удалось загрузить остальные комментарии. | Не удалось загрузить комментарии. Попробуйте ещё раз. | error says what to do |
| couldNotOpenPost | Не удалось открыть пост: $error | Не удалось открыть пост. Попробуйте ещё раз. | no raw technical error |
| notif: comment | прокомментировал(а) вашу публикацию | прокомментировал(а) ваш пост | glossary |
| notif: unavailable | Этот материал больше недоступен. | Этот пост или комментарий больше недоступен. | concrete |
| notif: permission_context | Разрешить уведомления Android для получения оповещений на этом устройстве? | Разрешить уведомления на этом телефоне? | shorter |
| notif: nearby_lost_pet | Рядом с вашим последним разрешённым местоположением ищут питомца | Рядом с вами ищут питомца | plain |
| notif: publication_removed_post | Модератор удалил вашу публикацию | Модератор удалил ваш пост | glossary |
| notif: publication_removed_lost_pet | Модератор удалил ваше объявление о пропавшем питомце | Модератор удалил ваше объявление о пропаже | glossary |
| notif: automatic_hint | Комментарии, ответы, напоминания о питомцах и возвращении включены автоматически. | Уведомления о комментариях, ответах и напоминания включены по умолчанию. | plain |
| notif: push_status | Доставка push | Push-уведомления | plain |
| notif: push_unavailable | Недоступна: нужны разрешение Android и настроенная доставка push. | Не работают: нужно разрешение Android и настроенные push-уведомления. | plain |
| notif: nearby_available | Доступно в радиусе 500 м от последнего разрешённого местоположения | Сообщим о пропавших питомцах в 500 м от вас | active, friendly |
| notif: nearby_permission_missing | Недоступно: нужны разрешение на геолокацию и включённые службы местоположения. | Не работает: включите геолокацию и разрешите её приложению. | what to do |
| notif: nearby_consent_missing | Недоступно: нужно согласие на приватное использование местоположения. | Не работает: сначала разрешите оповещения рядом. | plain |
| notif: nearby_unavailable | Недоступно: текущее местоположение устройства ещё не подтверждено. | Не работает: мы ещё не определили, где вы. | plain |
| notif: inbox_hint | Центр уведомлений работает, даже если push-уведомления запрещены в Android. | Уведомления в приложении работают, даже если push в Android выключены. | plain |
| notif: location_privacy | Приватность геолокации для оповещений | Оповещения рядом и местоположение | shorter title (the path in nearby_disclosure changes with it) |
| notif: nearby_disclosure | С вашего согласия и при разрешении Android Mushukistan приватно хранит только последнее местоположение устройства для оповещений о пропавших питомцах в радиусе 500 м. Оно обновляется при запуске или возвращении в приложение, без фонового отслеживания и истории перемещений. Отозвать согласие можно в Профиль → Настройки → Приватность геолокации для оповещений. При отзыве разрешения точка удалится, когда приложение снова подключится. | Если вы разрешите, мы будем хранить только последнее местоположение телефона — чтобы сообщать о пропавших питомцах в 500 м от вас. Обновляем его, когда вы открываете приложение; в фоне не следим и историю не храним. Отключить можно в «Профиль → Настройки → Оповещения рядом и местоположение». Если вы отзовёте разрешение, мы удалим точку при следующем подключении. | same facts, plain sentences (privacy text: review before applying) |
| notif: consent_allow | Разрешить приватные оповещения рядом | Разрешить оповещения рядом | shorter |
| notif: open_location_settings | Открыть разрешения геолокации Android | Открыть настройки геолокации | shorter |
| notif: sync_failed | Не удалось синхронизировать оповещения рядом. Повторим при активном приложении и подключении к сети. | Не удалось обновить оповещения рядом. Попробуем снова, когда появится интернет. | plain |

## 7. Errors and system messages
| Key | Current | Proposed | Reason |
|---|---|---|---|
| sessionUnavailableMessage | Вы по-прежнему вошли в аккаунт. Как только связь восстановится, мы проверим сессию автоматически. | Вы не вышли из аккаунта. Когда связь появится, всё заработает само. | no «сессия»; plain |
| restoringSession | Восстановление сессии... | Входим… | no «сессия»; ellipsis |
| signInRequiredTitle | Требуется аккаунт | Нужно войти | plain |
| signInRequiredMessage | Просматривать можно без аккаунта. Для этого действия нужно войти. | Смотреть можно и без аккаунта, а для этого действия войдите. | plain |
| couldNotSubmitReport | Не удалось отправить жалобу. Повторите попытку. | Не удалось отправить жалобу. Попробуйте ещё раз. | standard retry |
| feedback: sessionExpired | Сеанс истёк. Войдите снова, чтобы отправить отзыв. | Вы вышли из аккаунта. Войдите снова, чтобы отправить отзыв. | no «сеанс» |
| security: loadFailed | Не удалось загрузить настройки безопасности. | Не удалось загрузить настройки. Попробуйте ещё раз. | error says what to do |

## 8. Sign-in and account
| Key | Current | Proposed | Reason |
|---|---|---|---|
| orContinueWithEmail | или по электронной почте | или войдите по почте | complete phrase |
| confirmSignInPasswordHelp | Один раз введите пароль Mushukistan, чтобы продолжить. | Введите пароль от Mushukistan, чтобы продолжить. | «один раз» confuses |
| emailRequired | Укажите email. | Введите почту. | glossary |
| invalidEmail | Введите корректный email. | Проверьте адрес почты. | glossary; friendlier |
| verifyEmail | Подтвердите email | Подтвердите почту | glossary |
| confirmYourEmail | Подтвердите ваш email | Подтвердите почту | glossary; no «ваш» |
| verifyEmailWithoutAddress | Перед входом нужно подтвердить ваш email. | Чтобы войти, подтвердите почту по ссылке из письма. | what to do |
| verifyEmailWithAddress | Перед входом нужно подтвердить {email}. | Чтобы войти, подтвердите {email} по ссылке из письма. | what to do |
| resendVerification | Отправить подтверждение снова | Отправить письмо ещё раз | plain |
| confirmingEmail | Email подтверждается... | Подтверждаем почту… | active; ellipsis |
| emailVerifiedSignInNow | Email подтвержден. Теперь можно войти. | Почта подтверждена. Теперь можно войти. | glossary; ё |
| couldNotVerifyEmailLink | Не удалось подтвердить эту ссылку email. | Ссылка не сработала. Возможно, она устарела — запросите новое письмо. | what to do |
| googleSignInNoIdToken | Вход через Google не вернул ID token. | Не удалось войти через Google. Попробуйте ещё раз. | no technical detail |
| googleSignInNotConfigured | Вход через Google не настроен для этой сборки. | Вход через Google в этой версии недоступен. | no «сборка» |
| chooseLanguageSubtitle | Выберите язык, который хотите использовать в Mushukistan. | На каком языке показывать Mushukistan? | shorter |
| security: passwordSet | Включён | Задан | a password is set, not switched on |
| security: emailNeedsVerification | Требуется подтверждение | Не подтверждена | short status |
| security: currentPasswordIncorrect | Текущий пароль указан неверно. | Неверный текущий пароль. | shorter |
| security: required | Обязательное поле | Заполните это поле | says what to do |

## 9. Moderation and reports
| Key | Current | Proposed | Reason |
|---|---|---|---|
| reportedContentLabel | Обжалованный контент | На что пожаловались | **fix**: «обжалованный» means "appealed" |
| targetUnavailableExplanation | Обжалованный контент больше не существует. | Контента, на который пожаловались, больше нет. | **fix**: same |
| moderationReports | Жалобы модерации | Жалобы | shorter |
| saveModerationDecision | Сохранить решение модерации | Сохранить решение | shorter |
| historyDeletedMessage | Публикация удалена программно; предыдущая версия сохранена ниже. | Пост удалён автоматически. Последняя версия — ниже. | plain |
| reportFilterResolved | Решённые | Закрытые | matches the decision buttons |
| reportStatusResolved | Решена | Закрыта | same |
| noResolvedReports | Решённых жалоб нет. | Закрытых жалоб нет. | same |
| decisionResolveKeep | Решить без удаления | Закрыть без удаления | «решить жалобу» is unnatural |
| decisionRemove | Решить и удалить | Удалить и закрыть | same |
| decisionSuspend | Решить и заблокировать аккаунт | Заблокировать аккаунт и закрыть | same |
| decisionResolveKeepHint | Отметить жалобу как обработанную, ничего не удаляя. | Закрыть жалобу, ничего не удаляя. | shorter |
| decisionRemovePublicationHint | Публикация будет скрыта от всех, владелец получит уведомление. | Пост скроется от всех, автору придёт уведомление. | active; glossary |
| decisionRemoveCommentHint | Комментарий будет удалён из обсуждения. | Комментарий исчезнет из обсуждения. | active |
| decisionSuspendHint | Аккаунтом больше нельзя будет пользоваться. | Пользователь больше не сможет войти. | concrete |
| removalUnavailableHint | Контент уже недоступен, удалить его повторно нельзя. Решите или отклоните жалобу. | Контент уже недоступен. Закройте или отклоните жалобу. | shorter |
| confirmRemovalBody | «$title» будет скрыто из обычного просмотра, а жалоба будет отмечена как решённая. | «$title» скроется от пользователей, а жалоба закроется. | active |
| confirmSuspendBody | $name больше не сможет пользоваться аккаунтом, а жалоба будет отмечена как решённая. | $name больше не сможет войти, а жалоба закроется. | active |
| moderatorAccessRequired | Требуются права модератора. | Нужны права модератора. | plain |
| reportTargetPost | Публикация | Пост | glossary |
| reportContent | Пожаловаться на контент | Пожаловаться | short button |
| reasonRequired | Пожалуйста, укажите причину. | Укажите причину. | shorter |

## Totals
| Section | Changes |
|---|---|
| 1. Profile and settings | 28 |
| 2. Post creation | 26 |
| 3. Lost pets | 18 |
| 4. Rehoming | 22 |
| 5. Feed, map and leaderboard | 12 |
| 6. Comments and notifications | 21 |
| 7. Errors and system messages | 7 |
| 8. Sign-in and account | 19 |
| 9. Moderation and reports | 22 |
| **Total** | **175** |

## Unused strings (not proposed)
These keys are defined in `app_strings.dart` but no screen or test uses them, so they are left out
of the tables above. Proposal: delete them in all three languages when the copy is applied.
`adoptionAddSubtitle`, `adoptionPosts`, `attachLocationQuestion`, `backToAdd`, `cameraSubtitle`, `catObservationSubtitle`, `catsAndServices`, `chooseTypeFirst`, `communitySubtitle`, `descriptionHint`, `everythingCatsTitle`, `feedOnlyPost`, `feedSectionSubtitle`, `gallerySubtitle`, `locationDisclosureMessage`, `lostPetAddSubtitle`, `lostPetAlert`, `lostPetSubtitle`, `nearbyMap`, `observationLocation`, `useMyLocation`, `whatAreYouCreating`

## Applying (after approval)
- Change only the Russian arm of each string; English and Uzbek stay, except the **fix** for
  `createLostPetAlertHelp` (all three languages).
- Some keys are shared between screens (`additionalInformation`, `petName`/`petsName`): the change
  applies everywhere they appear.
- Widget tests that look for Russian text are updated with the strings.
- A native speaker should read sections 4 (help texts) and 6 (`nearby_disclosure`) before release.
