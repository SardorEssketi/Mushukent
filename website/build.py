"""Build the three static Mushukistan homepages with Python 3.10+."""

from __future__ import annotations

import hashlib
import html
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "dist"
BASE = "https://mushukistan.uz"

CONTENT = {
    "en": {
        "title": "Mushukistan — Cats, Lost Pets & Pet Community in Uzbekistan",
        "description": "Discover cats, help lost pets, find veterinary services, and connect with animal lovers in Uzbekistan through Mushukistan.",
        "nav": ["About", "Features", "Mission"], "open": "Open app", "theme": "Switch color theme", "menu": "Open menu", "close_menu": "Close menu", "navigation": "Main navigation", "skip": "Skip to content",
        "eyebrow": "A little more connected, a lot more caring · Uzbekistan",
        "hero": "A better world for cats starts with us.",
        "intro": "Discover cats around you, help lost pets find their way home, and connect with people who care.",
        "explore": "Explore Mushukistan", "map": "Explore map", "hero_note": "A place for the cats and people around us.",
        "about_kicker": "What is Mushukistan?", "about_title": "Every local act of care adds up.",
        "about_body": "Mushukistan brings cat observations, lost pet alerts, rehoming posts, nearby pet care places, and community conversations into one shared space. Start by exploring what is happening around you.",
        "features_kicker": "Made for real moments", "features_title": "From a sighting to a helping hand.",
        "features": [
            ("01", "See the city differently", "Find cats and community observations on an interactive map.", "/map", "Open the map"),
            ("02", "Help a lost pet get home", "Browse lost pet alerts and connect with owners when you can help.", "/feed", "See the feed"),
            ("03", "Share when help is needed", "Post an observation about an animal that needs assistance and give neighbors a place to respond.", "/feed", "Explore posts"),
            ("04", "Find nearby pet care", "Look for veterinary clinics, veterinary pharmacies, and pet stores in the map's place layers.", "/map", "Browse places"),
            ("05", "Be part of the conversation", "Follow community posts, leave a comment, and share useful information.", "/feed", "Meet the community"),
            ("06", "Help pets find a new home", "Browse rehoming posts and reach out when you can offer a caring home.", "/feed", "Browse rehoming posts"),
        ],
        "how_kicker": "How it works", "how_title": "Small steps can make a difference.",
        "steps": [
            ("Explore", "Browse the map and community to see what is happening nearby."),
            ("Share", "Add an observation or ask for help when an animal needs attention."),
            ("Connect", "Reach the people who can help, whether that means a lead, advice, or a new home."),
        ],
        "mission_kicker": "Our mission", "mission_title": "Care begins close to home.",
        "mission_body": "Mushukistan makes animal welfare more visible, accessible, and community-driven in Uzbekistan. A nearby observation, a timely reply, or a shared lost pet alert can help people act together for animals in their area.",
        "closing_kicker": "There is room for you here", "closing_title": "Come see who is waiting around the corner.",
        "closing_body": "Explore the community, find local pet care, and take part when you are ready.", "get_started": "Get started",
        "footer_tag": "A community for cats and the people who care for them.", "country": "Uzbekistan", "home": "Home", "app": "Application", "privacy": "Privacy policy", "terms": "Terms of service", "safety": "Child safety standards", "deletion": "Account deletion", "contact": "Contact", "language": "Language", "visual_alt": "Original illustration of a cat in a neighborhood with map markers and a connecting path",
    },
    "ru": {
        "title": "Mushukistan — кошки, потерявшиеся питомцы и сообщество в Узбекистане",
        "description": "Находите кошек поблизости, помогайте искать потерявшихся питомцев, находите ветеринарные услуги и общайтесь с любителями животных в Узбекистане.",
        "nav": ["О проекте", "Возможности", "Миссия"], "open": "Открыть приложение", "theme": "Сменить тему", "menu": "Открыть меню", "close_menu": "Закрыть меню", "navigation": "Основная навигация", "skip": "Перейти к содержимому",
        "eyebrow": "Больше связи, больше заботы · Узбекистан",
        "hero": "Лучший мир для кошек начинается с нас.",
        "intro": "Находите кошек рядом, помогайте потерявшимся питомцам вернуться домой и знакомьтесь с неравнодушными людьми.",
        "explore": "Открыть Mushukistan", "map": "Открыть карту", "hero_note": "Место для кошек и людей рядом с нами.",
        "about_kicker": "Что такое Mushukistan?", "about_title": "Каждый добрый поступок рядом важен.",
        "about_body": "Mushukistan объединяет наблюдения за кошками, объявления о пропавших питомцах, поиск нового дома, полезные места рядом и общение в одном пространстве. Начните с того, что происходит вокруг вас.",
        "features_kicker": "Для реальных ситуаций", "features_title": "От встречи до помощи.",
        "features": [
            ("01", "Взгляните на город иначе", "Находите кошек и наблюдения сообщества на интерактивной карте.", "/map", "Открыть карту"),
            ("02", "Помогите питомцу вернуться домой", "Смотрите объявления о пропавших питомцах и связывайтесь с владельцами, если можете помочь.", "/feed", "Смотреть ленту"),
            ("03", "Расскажите, если нужна помощь", "Опубликуйте наблюдение о животном, которому нужна помощь, чтобы соседи смогли откликнуться.", "/feed", "Смотреть публикации"),
            ("04", "Найдите помощь поблизости", "Ищите ветеринарные клиники, ветаптеки и зоомагазины на карте.", "/map", "Найти места"),
            ("05", "Станьте частью сообщества", "Читайте публикации, оставляйте комментарии и делитесь полезной информацией.", "/feed", "Открыть сообщество"),
            ("06", "Помогите найти новый дом", "Смотрите объявления о поиске дома и связывайтесь с владельцами, если готовы принять питомца.", "/feed", "Смотреть объявления"),
        ],
        "how_kicker": "Как это работает", "how_title": "Небольшие шаги могут многое изменить.",
        "steps": [
            ("Исследуйте", "Посмотрите карту и ленту сообщества, чтобы узнать, что происходит рядом."),
            ("Делитесь", "Добавьте наблюдение или попросите помощи, когда животному нужно внимание."),
            ("Общайтесь", "Свяжитесь с теми, кто может помочь советом, информацией или новым домом."),
        ],
        "mission_kicker": "Наша миссия", "mission_title": "Забота начинается рядом.",
        "mission_body": "Mushukistan делает заботу о животных заметнее, доступнее и ближе к сообществу в Узбекистане. Наблюдение по соседству, своевременный ответ или объявление о пропаже помогают людям действовать вместе.",
        "closing_kicker": "Здесь есть место и для вас", "closing_title": "Узнайте, кто ждёт за углом.",
        "closing_body": "Исследуйте сообщество, находите помощь рядом и присоединяйтесь, когда будете готовы.", "get_started": "Начать",
        "footer_tag": "Сообщество для кошек и людей, которым они небезразличны.", "country": "Узбекистан", "home": "Главная", "app": "Приложение", "privacy": "Политика конфиденциальности", "terms": "Условия использования", "safety": "Стандарты безопасности детей", "deletion": "Удаление аккаунта", "contact": "Связаться", "language": "Язык", "visual_alt": "Авторская иллюстрация кошки в районе с отметками на карте и соединяющим маршрутом",
    },
    "uz": {
        "title": "Mushukistan — O‘zbekistondagi mushuklar, yo‘qolgan uy hayvonlari va hamjamiyat",
        "description": "Mushukistan orqali yaqin atrofdagi mushuklarni toping, yo‘qolgan hayvonlarga yordam bering, veterinariya xizmatlarini izlang va O‘zbekistondagi hamjamiyatga qo‘shiling.",
        "nav": ["Biz haqimizda", "Imkoniyatlar", "Maqsadimiz"], "open": "Ilovani ochish", "theme": "Rang mavzusini almashtirish", "menu": "Menyuni ochish", "close_menu": "Menyuni yopish", "navigation": "Asosiy navigatsiya", "skip": "Asosiy mazmunga o‘tish",
        "eyebrow": "Ko‘proq birdamlik, ko‘proq g‘amxo‘rlik · O‘zbekiston",
        "hero": "Mushuklar uchun yaxshiroq dunyo bizdan boshlanadi.",
        "intro": "Yaqiningizdagi mushuklarni kashf eting, yo‘qolgan uy hayvonlariga uyga qaytishda yordam bering va mehribon insonlar bilan bog‘laning.",
        "explore": "Mushukistanni kashf etish", "map": "Xaritani ochish", "hero_note": "Atrofimizdagi mushuklar va insonlar uchun joy.",
        "about_kicker": "Mushukistan nima?", "about_title": "Yaqinimizdagi har bir ezgu ish ahamiyatli.",
        "about_body": "Mushukistan mushuklar haqidagi kuzatuvlar, yo‘qolgan hayvonlar e’lonlari, yangi uy qidirish, yaqin atrofdagi foydali joylar va suhbatlarni bir joyga jamlaydi. Atrofingizda nimalar bo‘layotganini ko‘rishdan boshlang.",
        "features_kicker": "Haqiqiy vaziyatlar uchun", "features_title": "Uchrashuvdan yordamgacha.",
        "features": [
            ("01", "Shaharni boshqacha ko‘ring", "Interaktiv xaritada mushuklar va hamjamiyat kuzatuvlarini toping.", "/map", "Xaritani ochish"),
            ("02", "Yo‘qolgan hayvonga uyga qaytishda yordam bering", "Yo‘qolgan hayvonlar haqidagi e’lonlarni ko‘ring va yordam bera olsangiz, egasi bilan bog‘laning.", "/feed", "Tasmaga o‘tish"),
            ("03", "Yordam kerak bo‘lsa, xabar bering", "Yordamga muhtoj hayvon haqida kuzatuv joylang, qo‘shnilar javob bera olsin.", "/feed", "Postlarni ko‘rish"),
            ("04", "Yaqin atrofda yordam toping", "Xaritada veterinariya klinikalari, vetdorixonalar va hayvonlar do‘konlarini izlang.", "/map", "Joylarni ko‘rish"),
            ("05", "Suhbatga qo‘shiling", "Hamjamiyat postlarini o‘qing, izoh qoldiring va foydali ma’lumot ulashing.", "/feed", "Hamjamiyatni ochish"),
            ("06", "Hayvonlarga yangi uy topishga ko‘maklashing", "Yangi uy qidirilayotgan hayvonlar e’lonlarini ko‘ring va yordam bera olsangiz bog‘laning.", "/feed", "E’lonlarni ko‘rish"),
        ],
        "how_kicker": "Bu qanday ishlaydi", "how_title": "Kichik qadamlar katta farq qiladi.",
        "steps": [
            ("Kashf eting", "Yaqin atrofdagi voqealarni ko‘rish uchun xarita va hamjamiyatni varaqlang."),
            ("Ulashib boring", "Hayvonga e’tibor kerak bo‘lsa, kuzatuv qo‘shing yoki yordam so‘rang."),
            ("Bog‘laning", "Maslahat, ma’lumot yoki yangi uy taklif qila oladigan insonlar bilan aloqa qiling."),
        ],
        "mission_kicker": "Maqsadimiz", "mission_title": "G‘amxo‘rlik yonimizdan boshlanadi.",
        "mission_body": "Mushukistan O‘zbekistonda hayvonlarga g‘amxo‘rlikni ko‘rinadigan, qulay va hamjamiyatga yaqin qiladi. Qo‘shni kuzatuvi, o‘z vaqtida berilgan javob yoki yo‘qolgan hayvon e’loni odamlarning birga harakat qilishiga yordam beradi.",
        "closing_kicker": "Siz uchun ham joy bor", "closing_title": "Yaqiningizda kim kutayotganini ko‘ring.",
        "closing_body": "Hamjamiyatni kashf eting, yaqin atrofdagi yordamni toping va tayyor bo‘lganingizda qo‘shiling.", "get_started": "Boshlash",
        "footer_tag": "Mushuklar va ularga befarq bo‘lmagan insonlar hamjamiyati.", "country": "O‘zbekiston", "home": "Bosh sahifa", "app": "Ilova", "privacy": "Maxfiylik siyosati", "terms": "Foydalanish shartlari", "safety": "Bolalar xavfsizligi standartlari", "deletion": "Hisobni o‘chirish", "contact": "Bog‘lanish", "language": "Til", "visual_alt": "Xarita belgilari va yo‘l bilan mahalladagi mushukning asl illyustratsiyasi",
    },
}


def e(value: str) -> str:
    return html.escape(value, quote=True)


def asset(name: str, content: bytes) -> str:
    digest = hashlib.sha256(content).hexdigest()[:12]
    filename = f"{Path(name).stem}.{digest}{Path(name).suffix}"
    (OUT / "landing-assets" / filename).write_bytes(content)
    return "/landing-assets/" + filename


def page(lang: str, c: dict, assets: dict[str, str]) -> str:
    path = "/" if lang == "en" else f"/{lang}/"
    hreflang = "\n".join(f'<link rel="alternate" hreflang="{code}" href="{BASE}{url}">' for code, url in [("en", "/"), ("ru", "/ru/"), ("uz", "/uz/"), ("x-default", "/")])
    links = "".join(f'<a href="{url}" hreflang="{code}" lang="{code}" aria-current="{"page" if code == lang else "false"}">{label}</a>' for code, url, label in [("en", "/", "EN"), ("ru", "/ru/", "RU"), ("uz", "/uz/", "UZ")])
    features = "\n".join(f'<article class="feature"><span class="feature-number">{n}</span><div><h3>{e(title)}</h3><p>{e(body)}</p><a class="text-link" href="{url}">{e(action)} <span aria-hidden="true">↗</span></a></div></article>' for n, title, body, url, action in c["features"])
    steps = "\n".join(f'<li><span class="step-number">0{i}</span><h3>{e(title)}</h3><p>{e(body)}</p></li>' for i, (title, body) in enumerate(c["steps"], 1))
    structured = json.dumps([
        {"@context": "https://schema.org", "@type": "Organization", "name": "Mushukistan", "url": BASE, "logo": BASE + assets["logo"]},
        {"@context": "https://schema.org", "@type": "WebSite", "name": "Mushukistan", "url": BASE, "inLanguage": ["en", "ru", "uz"]},
    ], ensure_ascii=False).replace("<", "\\u003c")
    return f'''<!doctype html>
<html lang="{lang}" data-theme="auto">
<head>
  <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light dark"><meta name="theme-color" content="#fff8f0">
  <title>{e(c['title'])}</title><meta name="description" content="{e(c['description'])}">
  <link rel="canonical" href="{BASE}{path}">
  {hreflang}
  <meta property="og:type" content="website"><meta property="og:site_name" content="Mushukistan"><meta property="og:locale" content="{'en_US' if lang == 'en' else 'ru_RU' if lang == 'ru' else 'uz_UZ'}">
  <meta property="og:title" content="{e(c['title'])}"><meta property="og:description" content="{e(c['description'])}"><meta property="og:url" content="{BASE}{path}"><meta property="og:image" content="{BASE}{assets['social'][lang]}"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="{e(c['footer_tag'])}">
  <meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="{e(c['title'])}"><meta name="twitter:description" content="{e(c['description'])}"><meta name="twitter:image" content="{BASE}{assets['social'][lang]}">
  <link rel="icon" type="image/png" href="{assets['logo']}"><link rel="preload" as="image" href="{assets['hero']}">
  <link rel="stylesheet" href="{assets['css']}"><script src="{assets['js']}" defer></script>
  <script type="application/ld+json">{structured}</script>
  <noscript><style>.theme-toggle,.menu-toggle{{display:none!important}}@media(max-width:800px){{.mobile-nav[hidden]{{display:flex!important;flex-direction:column;padding-bottom:16px}}.mobile-nav[hidden] a{{padding:14px 0;border-top:1px solid var(--line)}}}}</style></noscript>
</head>
<body>
  <a class="skip-link" href="#main">{e(c['skip'])}</a>
  <header class="site-header"><div class="container header-inner">
    <a class="brand" href="{path}" aria-label="Mushukistan — {e(c['home'])}"><img src="{assets['logo']}" width="40" height="40" alt=""><span>Mushukistan<span class="brand-dot">.</span></span></a>
    <nav class="desktop-nav" aria-label="{e(c['navigation'])}"><a href="#about">{e(c['nav'][0])}</a><a href="#features">{e(c['nav'][1])}</a><a href="#mission">{e(c['nav'][2])}</a></nav>
    <div class="header-actions"><div class="language" role="group" aria-label="{e(c['language'])}">{links}</div><button class="theme-toggle" type="button" aria-pressed="false" aria-label="{e(c['theme'])}" title="{e(c['theme'])}"><svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M12 2.5v2m0 15v2m9.5-9.5h-2m-15 0h-2m16.22-6.72-1.42 1.42M6.7 17.3l-1.42 1.42m13.44 0-1.42-1.42M6.7 6.7 5.28 5.28M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg></button><a class="button button-small header-cta" href="/feed">{e(c['open'])} <span aria-hidden="true">↗</span></a><button class="menu-toggle" type="button" aria-label="{e(c['menu'])}" data-open-label="{e(c['menu'])}" data-close-label="{e(c['close_menu'])}" aria-expanded="false" aria-controls="mobile-nav"><span></span><span></span></button></div>
  </div><nav id="mobile-nav" class="mobile-nav container" aria-label="{e(c['navigation'])}" hidden><a href="#about">{e(c['nav'][0])}</a><a href="#features">{e(c['nav'][1])}</a><a href="#mission">{e(c['nav'][2])}</a><a href="/feed">{e(c['open'])} ↗</a><div class="mobile-languages" role="group" aria-label="{e(c['language'])}">{links}</div></nav></header>
  <main id="main"><section class="hero"><div class="container hero-grid"><div class="hero-copy"><p class="eyebrow"><span class="eyebrow-line"></span>{e(c['eyebrow'])}</p><h1>{e(c['hero'])}</h1><p class="hero-intro">{e(c['intro'])}</p><div class="hero-actions"><a class="button button-primary" href="/feed">{e(c['explore'])}<span aria-hidden="true">↗</span></a><a class="button button-quiet" href="/map">{e(c['map'])}<span aria-hidden="true">→</span></a></div><p class="hero-footnote"><span class="small-paw" aria-hidden="true">✦</span>{e(c['hero_note'])}</p></div><div class="hero-art"><img src="{assets['hero']}" width="720" height="730" alt="{e(c['visual_alt'])}" fetchpriority="high"></div></div></section>
  <section id="about" class="about section"><div class="container about-grid"><div><p class="section-kicker">{e(c['about_kicker'])}</p><h2>{e(c['about_title'])}</h2></div><div class="about-body"><p>{e(c['about_body'])}</p><div class="about-rule"><span>UZ</span><span>✦</span><span>01 / 03</span></div></div></div></section>
  <section id="features" class="features section"><div class="container"><div class="section-heading"><div><p class="section-kicker">{e(c['features_kicker'])}</p><h2>{e(c['features_title'])}</h2></div><span class="section-mark" aria-hidden="true">✳</span></div><div class="feature-grid">{features}</div></div></section>
  <section id="how" class="how section"><div class="container how-layout"><div><p class="section-kicker">{e(c['how_kicker'])}</p><h2>{e(c['how_title'])}</h2><a class="button button-outline" href="/map">{e(c['map'])}<span aria-hidden="true">↗</span></a></div><ol class="steps">{steps}</ol></div></section>
  <section id="mission" class="mission section"><div class="container mission-panel"><div class="mission-symbol" aria-hidden="true">✳</div><div><p class="section-kicker">{e(c['mission_kicker'])}</p><h2>{e(c['mission_title'])}</h2><p>{e(c['mission_body'])}</p></div></div></section>
  <section class="final-cta section"><div class="container"><p class="section-kicker">{e(c['closing_kicker'])}</p><h2>{e(c['closing_title'])}</h2><p>{e(c['closing_body'])}</p><a class="button button-primary" href="/feed">{e(c['get_started'])}<span aria-hidden="true">↗</span></a></div></section></main>
  <footer class="site-footer"><div class="container footer-top"><div><a class="brand" href="{path}"><img src="{assets['logo']}" width="40" height="40" alt=""><span>Mushukistan<span class="brand-dot">.</span></span></a><p>{e(c['footer_tag'])}</p></div><nav aria-label="{e(c['navigation'])}"><a href="{path}">{e(c['home'])}</a><a href="/feed">{e(c['app'])}</a><a href="/map">{e(c['map'])}</a><a href="/privacy">{e(c['privacy'])}</a><a href="/legal/terms">{e(c['terms'])}</a><a href="/child-safety">{e(c['safety'])}</a><a href="/delete-account">{e(c['deletion'])}</a><a href="mailto:sardor.datascience@gmail.com">{e(c['contact'])}</a></nav></div><div class="container footer-bottom"><span>© Mushukistan</span><span>{e(c['country'])} · {e(c['footer_tag'])}</span></div></footer>
</body></html>'''


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "landing-assets").mkdir(parents=True)
    assets = {
        "css": asset("site.css", (ROOT / "src/site.css").read_bytes()),
        "js": asset("site.js", (ROOT / "src/site.js").read_bytes()),
        "hero": asset("hero.svg", (ROOT / "src/hero.svg").read_bytes()),
        "social": {lang: asset(f"social-{lang}.png", (ROOT / f"src/social-{lang}.png").read_bytes()) for lang in CONTENT},
        "logo": asset("logo.png", (ROOT / "src/logo.png").read_bytes()),
    }
    for lang, content in CONTENT.items():
        target = OUT if lang == "en" else OUT / lang
        target.mkdir(parents=True, exist_ok=True)
        (target / "index.html").write_text(page(lang, content, assets), encoding="utf-8")
    (OUT / "robots.txt").write_text("User-agent: *\nAllow: /\nSitemap: https://mushukistan.uz/sitemap.xml\n", encoding="utf-8")
    urls = "".join(f"<url><loc>{BASE}{path}</loc></url>" for path in ["/", "/ru/", "/uz/"])
    (OUT / "sitemap.xml").write_text(f'<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">{urls}</urlset>', encoding="utf-8")
    print(f"Built {OUT}")


if __name__ == "__main__":
    main()
