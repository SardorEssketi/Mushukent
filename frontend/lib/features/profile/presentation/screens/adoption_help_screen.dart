import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/language_controller.dart';

class AdoptionHelpScreen extends ConsumerWidget {
  const AdoptionHelpScreen({super.key});

  static final Uri _keepingRulesUrl =
      Uri.parse('https://advice.adliya.uz/uz/document/2728');
  static final Uri _vetPassportUrl =
      Uri.parse('https://hukumat.uz/oz/advice/591/document/2341');
  static final Uri _strayAnimalsUrl =
      Uri.parse('https://gov.uz/en/advice/NaN/document/2727');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final language = ref.watch(appLanguageProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(strings.adoptionHelp)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              _Notice(text: strings.adoptionHelpDisclaimer),
              const SizedBox(height: 16),
              _Section(
                icon: Icons.search_outlined,
                title: strings.adoptionBeforeYouTakeCat,
                items: _beforeTakingCat(language),
              ),
              const SizedBox(height: 12),
              _Section(
                icon: Icons.medical_services_outlined,
                title: strings.adoptionVetProcedure,
                items: _vetProcedure(language),
              ),
              const SizedBox(height: 12),
              _Section(
                icon: Icons.home_outlined,
                title: strings.adoptionLegalCareRules,
                items: _homeRules(language),
              ),
              const SizedBox(height: 18),
              Text(
                strings.adoptionOfficialSources,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              _SourceTile(
                label: strings.adoptionSourceKeepingRules,
                url: _keepingRulesUrl,
              ),
              _SourceTile(
                label: strings.adoptionSourceVetPassport,
                url: _vetPassportUrl,
              ),
              _SourceTile(
                label: strings.adoptionSourceStrayAnimals,
                url: _strayAnimalsUrl,
              ),
              const SizedBox(height: 8),
              Text(
                _sourceNote(language),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              color: colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.items,
  });

  final IconData icon;
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final item in items) _Bullet(text: item),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Icon(Icons.circle, size: 6),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.label, required this.url});

  final String label;
  final Uri url;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.open_in_new_outlined),
      title: Text(label),
      subtitle: Text(url.host),
      onTap: () => launchUrl(url, mode: LaunchMode.externalApplication),
    );
  }
}

List<String> _beforeTakingCat(AppLanguage language) {
  return switch (language) {
    AppLanguage.uzbek => [
        'Mushuk egasiz ekaniga ishonch hosil qiling: yaqin atrofdagi odamlar, qo‘shnilar va mavjud e’lonlarni tekshiring.',
        'Mushuk jarohatlangan, tajovuzkor yoki quturish alomatlariga o‘xshash holatda bo‘lsa, qo‘l bilan ushlamang; veterinariya xizmati yoki qarovsiz hayvonlarni tutish xizmatiga murojaat qiling.',
        'Agar mushuk kimdandir olinayotgan bo‘lsa, beruvchi shaxsdan veterinariya hujjatlari bor-yo‘qligini so‘rang.',
      ],
    AppLanguage.russian => [
        'Убедитесь, что у кошки нет владельца: проверьте двор, соседей и существующие объявления.',
        'Если кошка ранена, агрессивна или есть признаки, похожие на бешенство, не ловите ее руками; обратитесь в ветеринарную службу или службу отлова безнадзорных животных.',
        'Если кошку передает другой человек, попросите имеющиеся ветеринарные документы.',
      ],
    AppLanguage.english => [
        'Make sure the cat is truly without an owner: check nearby residents, neighbors, and existing notices.',
        'If the cat is injured, aggressive, or shows signs that could indicate rabies, do not handle it by hand; contact a veterinarian or the stray-animal catching service.',
        'If another person is giving you the cat, ask for any available veterinary documents.',
      ],
  };
}

List<String> _vetProcedure(AppLanguage language) {
  return switch (language) {
    AppLanguage.uzbek => [
        'Mushukni imkon qadar tezroq veterinarga olib boring: umumiy ko‘rik, parazitlarga qarshi ishlov, emlash va sterilizatsiya masalasini tekshiring.',
        'Doimiy yoki vaqtincha yashash joyingiz bo‘yicha davlat veterinariya xizmati vakiliga murojaat qilib, identifikatsiya va hisobga olish tartibini aniqlang.',
        'Veterinariya pasportida hayvonning identifikatsiya raqami, egasi, emlashlar, davolash va profilaktika ishlari qayd etiladi.',
        'Mushuk sotib olingan yoki hadya qilingan bo‘lsa, yangi egasi veterinariya xizmatida ro‘yxatdan o‘tkazish masalasini 7 kun ichida aniqlashi kerak.',
      ],
    AppLanguage.russian => [
        'Как можно быстрее покажите кошку ветеринару: общий осмотр, обработка от паразитов, вакцинация и вопрос стерилизации.',
        'Обратитесь к представителю государственной ветеринарной службы по месту постоянного или временного проживания, чтобы уточнить идентификацию и учет.',
        'В ветеринарном паспорте фиксируются идентификационный номер животного, владелец, вакцинации, лечение и профилактика.',
        'Если кошка куплена или получена в дар, новый владелец должен уточнить регистрацию в ветеринарной службе в течение 7 дней.',
      ],
    AppLanguage.english => [
        'Take the cat to a veterinarian as soon as possible for a general exam, parasite treatment, vaccinations, and sterilization advice.',
        'Contact the state veterinary service representative for your permanent or temporary residence to confirm identification and registration steps.',
        'The veterinary passport records the animal identification number, owner, vaccinations, treatment, and preventive care.',
        'If the cat was bought or received as a gift, the new owner should confirm registration with the veterinary service within 7 days.',
      ],
  };
}

List<String> _homeRules(AppLanguage language) {
  return switch (language) {
    AppLanguage.uzbek => [
        'Ko‘p qavatli uyning alohida kvartirasida qoidalarda 1 ta mushuk saqlashga ruxsat berilishi ko‘rsatilgan; qo‘shnilar va uy-joy mulkdorlari shirkati roziligi talab qilinishi mumkin.',
        'Mushuklarni zinapoya, chordoq, yerto‘la, oshxona, balkon va boshqa umumiy foydalanish joylarida saqlamang.',
        'Mushukni tashlab ketish, qarovsiz qoldirish, jarohat yetkazish yoki azob berish taqiqlanadi.',
        'Mushukni sotish, sotib olish, olib kelish yoki olib ketishda hayvon sog‘lig‘i haqidagi veterinariya hujjatlari va qonunchilikda talab qilingan boshqa hujjatlar kerak bo‘lishi mumkin.',
      ],
    AppLanguage.russian => [
        'В отдельной квартире многоэтажного дома правила предусматривают содержание 1 кошки; может требоваться согласие соседей и товарищества собственников жилья.',
        'Не держите кошек на лестничных площадках, чердаках, в подвалах, кухнях, на балконах и в других местах общего пользования.',
        'Запрещено бросать кошку, оставлять без присмотра, причинять травмы или страдания.',
        'При продаже, покупке, ввозе или вывозе кошки могут потребоваться ветеринарные документы о здоровье животного и другие документы, предусмотренные законодательством.',
      ],
    AppLanguage.english => [
        'For a separate apartment in a multi-storey building, the rules mention keeping 1 cat; neighbor and homeowners-association consent may be required.',
        'Do not keep cats in common-use areas such as stairwells, attics, basements, kitchens, balconies, or shared verandas.',
        'Do not abandon the cat, leave it neglected, injure it, or cause suffering.',
        'Sale, purchase, import, or transport of a cat may require veterinary health documents and other documents required by law.',
      ],
  };
}

String _sourceNote(AppLanguage language) {
  return switch (language) {
    AppLanguage.uzbek =>
      'Manbalar: Adliya huquqiy maslahat sahifasi, Hukumat portali va davlat veterinariya/qarovsiz hayvonlar bo‘yicha ma’lumotlar.',
    AppLanguage.russian =>
      'Источники: правовая консультация Adliya, правительственный портал и материалы о государственной ветеринарной службе/безнадзорных животных.',
    AppLanguage.english =>
      'Sources: Adliya legal guidance, the government portal, and state veterinary/stray-animal service information.',
  };
}
