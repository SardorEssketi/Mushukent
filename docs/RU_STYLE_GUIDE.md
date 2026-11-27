# Russian UI style guide

For every Russian string in the app (`app_strings.dart`, `notification_strings.dart`,
`feedback_strings.dart`, `account_security_strings.dart`, in-screen texts). Legal documents keep
their own wording.

## Voice
- Address the user as «вы» (lower case). Be friendly and calm, never bureaucratic.
- Short, plain sentences: one thought each. Prefer two short sentences to one long one.
- Active voice, with «мы» for the app: «Мы удалим пост», not «Пост будет удалён».
- No officialese: no «осуществить», «данный», «в целях», «вошедшие в аккаунт пользователи»,
  «последнее обнаружение», «повторите попытку», «не представляется возможным».
- Say what the person gets, not how the system works: «Объявление уберём с карты», not
  «Объявление исчезнет из выдачи».

## Buttons and titles
- Buttons are verbs, as short as possible: «Опубликовать», «Сохранить», «Удалить», «Войти».
- In a confirmation dialog the title asks the question («Удалить пост?») and the buttons answer
  it («Удалить» / «Отмена»).
- Titles are short noun phrases without a full stop: «Мои объявления», «Черновик поста».

## Errors and empty states
- Say what happened, then what to do: «Не удалось загрузить фото. Проверьте интернет и попробуйте
  ещё раз.»
- The retry phrase is always «Попробуйте ещё раз.» (button: «Повторить»).
- Never show raw technical details (`ID token`, `$error`, «сессия», «бэкенд»).
- Empty states say what will appear here and, if useful, how: «Пока нет сохранённых постов.»

## Glossary
Pick «пост», «объявление» or «публикация» by where the string is shown, not by the key name: a
string reused across post types needs the generic word, or a separate string per type.

| Use | Not | Meaning |
|---|---|---|
| **пост** | публикация, материал | a cat post or a «Кошке нужна помощь» post |
| **объявление** | пост, публикация | a lost-pet or rehoming post («объявление о пропаже», «объявление о пристройстве») |
| **публикация** | пост, материал | only the generic word, where the text can refer to any type: «Публикация недоступна», a list or menu shared by all types (owner decision, 2026-11-28) |
| **кошка** | животное, питомец | cat posts and «Кошке нужна помощь» |
| **питомец** | животное, кошка | lost-pet and rehoming posts (may be any pet) |
| **имя питомца** | — | the name field in lost-pet and rehoming posts: the owner kept «Имя питомца» (2026-11-28); «кличка» may appear in running text; «имя кошки» stays for cat posts |
| **пристройство** / «найти дом» | усыновление, передача | rehoming |
| **пропал / нашёлся** | обнаружение, найден | lost pets: «Где видели в последний раз», «Питомец нашёлся» |
| **войти / выйти / вход** | авторизоваться, вошедшие пользователи | sign in / out; «те, кто вошёл в аккаунт» |
| **аккаунт** | учётная запись, сессия, сеанс | the user's account |
| **почта** | email (in sentences) | «Подтвердите почту»; the field label may stay «Email» |
| **черновик** | — | a saved, unpublished post |
| **место** | местоположение (for a post) | the point of a post on the map |
| **местоположение** | геопозиция | where the user's device is |
| **геолокация** | — | only the Android permission and its settings |
| **жалоба** | репорт | a report; moderators «закрывают» or «отклоняют» it |
| **модератор** | администратор | — |
| **лайк** | отметка «нравится» | — |
| **уведомление** | оповещение | in-app and push; for the nearby lost-pet alerts say «пропавшие питомцы рядом» / «оповещения о пропавших питомцах рядом», never «оповещения рядом» |
| **интернет** | подключение, соединение | in error messages: «Проверьте интернет» |

## Spelling and typography
- Always write «ё»: удалён, сохранён, ещё, тёмная, моё.
- Russian quotes «ёлочки»; dash «—» with spaces; ellipsis «…» as one character.
- Numbers and units: «500 м», «5 с»; phone numbers as `+998 90 123 45 67`.
- Gender-neutral wording where possible; «(а)» only when a past-tense verb after a name cannot
  be avoided.
