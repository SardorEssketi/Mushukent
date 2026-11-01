"""Focused checks of the generated public site and integration contract."""

from __future__ import annotations

import json
import struct
import re
import unittest
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse

from build import CONTENT, OUT, PLAY_URL, ROOT, favicon_ico, main


class Tags(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.tags: list[tuple[str, dict[str, str]]] = []
        self.text: list[str] = []
        self.ld_json: list[str] = []
        self._json = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        self.tags.append((tag, values))
        if tag == "script" and values.get("type") == "application/ld+json":
            self._json = True

    def handle_endtag(self, tag: str) -> None:
        if tag == "script":
            self._json = False

    def handle_data(self, data: str) -> None:
        if self._json:
            self.ld_json.append(data)
        else:
            self.text.append(data)

    def all(self, tag: str) -> list[dict[str, str]]:
        return [attrs for name, attrs in self.tags if name == tag]


class SiteBuildTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        main()

    def test_localized_html_is_complete_without_js(self) -> None:
        for lang, content in CONTENT.items():
            with self.subTest(lang=lang):
                page = OUT / ("index.html" if lang == "ru" else f"{lang}/index.html")
                document = page.read_text(encoding="utf-8")
                parsed = Tags()
                parsed.feed(document)
                self.assertEqual(parsed.all("html")[0]["lang"], lang)
                self.assertEqual(len(parsed.all("h1")), 1)
                self.assertGreaterEqual(len(parsed.all("h2")), 5)
                self.assertIn(content["hero"], " ".join(parsed.text))
                self.assertIn(content["mission_body"], " ".join(parsed.text))
                self.assertNotIn("flutter_bootstrap.js", document)
                self.assertNotIn('class="about-rule"', document)
                self.assertEqual(len(parsed.all("nav")), 3)

    def test_metadata_and_assets(self) -> None:
        for lang, content in CONTENT.items():
            with self.subTest(lang=lang):
                page = OUT / ("index.html" if lang == "ru" else f"{lang}/index.html")
                document = page.read_text(encoding="utf-8")
                parsed = Tags()
                parsed.feed(document)
                canonical = next(a["href"] for a in parsed.all("link") if a.get("rel") == "canonical")
                self.assertEqual(canonical, "https://mushukistan.uz" + ("/" if lang == "ru" else f"/{lang}/"))
                alternates = {a["hreflang"]: a["href"] for a in parsed.all("link") if a.get("rel") == "alternate"}
                self.assertEqual(set(alternates), {"en", "ru", "uz", "x-default"})
                self.assertEqual(len(parsed.all("title")), 1)
                self.assertIn(content["title"].split(" — ")[0], document)
                meta = {a.get("name"): a.get("content") for a in parsed.all("meta")}
                self.assertEqual(meta["description"], content["description"])
                self.assertEqual(meta["twitter:card"], "summary_large_image")
                properties = {a.get("property"): a.get("content") for a in parsed.all("meta")}
                self.assertEqual(properties["og:image:alt"], content["footer_tag"])
                self.assertIn(f"social-{lang}.", properties["og:image"])
                self.assertTrue((OUT / properties["og:image"].removeprefix("https://mushukistan.uz/")).is_file())
                schemas = json.loads("".join(parsed.ld_json))
                self.assertEqual({x["@type"] for x in schemas}, {"Organization", "WebSite"})
                for a in parsed.all("link") + parsed.all("script") + parsed.all("img"):
                    path = a.get("href") or a.get("src")
                    if path and path.startswith("/landing-assets/"):
                        self.assertTrue((OUT / path.removeprefix("/")).is_file(), path)
                for a in parsed.all("a"):
                    href = a.get("href", "")
                    self.assertTrue(href.startswith(("/", "#", "mailto:")) or href == PLAY_URL, href)
                    if href.startswith("/"):
                        self.assertFalse(urlparse(href).netloc)
                # Hero, mobile menu and closing call to action offer Google Play and the web app;
                # the header offers both as compact buttons.
                self.assertEqual(document.count(f'<a class="button button-store" href="{PLAY_URL}">'), 3)
                self.assertEqual(document.count('<a class="button button-primary" href="/feed">'), 3)
                self.assertIn(f'<a class="button button-small header-cta header-play" href="{PLAY_URL}">', document)
                self.assertIn('<a class="button button-small header-cta header-open" href="/feed">', document)
                self.assertIn('href="/privacy"', document)
                self.assertNotIn('href="/child-safety"', document)
                self.assertIn('href="/delete-account"', document)

    def test_russian_is_the_default_and_legacy_url_is_not_indexed(self) -> None:
        ru = (OUT / "index.html").read_text(encoding="utf-8")
        en = (OUT / "en/index.html").read_text(encoding="utf-8")
        self.assertIn('<html lang="ru"', ru)
        self.assertIn('<html lang="en"', en)
        self.assertFalse((OUT / "ru").exists(), "the old /ru/ page must not be built any more")
        for document in (ru, en):
            alternates = dict(re.findall(r'<link rel="alternate" hreflang="([^"]+)" href="([^"]+)">', document))
            self.assertEqual(alternates, {"ru": "https://mushukistan.uz/", "en": "https://mushukistan.uz/en/",
                                          "uz": "https://mushukistan.uz/uz/", "x-default": "https://mushukistan.uz/"})
        sitemap = (OUT / "sitemap.xml").read_text(encoding="utf-8")
        self.assertNotIn("/ru/", sitemap)

    def test_sitemap_robots_and_manifest(self) -> None:
        sitemap = ET.parse(OUT / "sitemap.xml")
        locs = [e.text for e in sitemap.findall(".//{http://www.sitemaps.org/schemas/sitemap/0.9}loc")]
        self.assertEqual(locs, ["https://mushukistan.uz/", "https://mushukistan.uz/en/", "https://mushukistan.uz/uz/"])
        robots = (OUT / "robots.txt").read_text(encoding="utf-8")
        self.assertIn("Allow: /", robots)
        self.assertIn("Sitemap: https://mushukistan.uz/sitemap.xml", robots)
        manifest = json.loads((ROOT.parent / "frontend/web/manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["start_url"], "/feed")
        self.assertEqual(manifest["scope"], "/")

    def test_each_page_declares_one_current_icon(self) -> None:
        logo = (ROOT / "src/logo.png").read_bytes()
        for lang in CONTENT:
            with self.subTest(lang=lang):
                page = OUT / ("index.html" if lang == "ru" else f"{lang}/index.html")
                parsed = Tags()
                parsed.feed(page.read_text(encoding="utf-8"))
                icons = [a for a in parsed.all("link") if "icon" in a.get("rel", "").split()]
                self.assertEqual(len(icons), 1, icons)  # no competing declarations
                self.assertEqual(icons[0].get("type"), "image/png")
                href = icons[0]["href"]
                self.assertRegex(href, r"^/landing-assets/logo\.[0-9a-f]{12}\.png$")
                self.assertEqual((OUT / href.lstrip("/")).read_bytes(), logo)
                self.assertFalse(
                    [a for a in parsed.all("link") if "shortcut" in a.get("rel", "")]
                )

    def test_favicon_ico_is_the_current_icon_in_ico_format(self) -> None:
        data = (OUT / "favicon.ico").read_bytes()
        logo = (ROOT / "src/logo.png").read_bytes()
        self.assertEqual(struct.unpack("<HHH", data[:6]), (0, 1, 1))  # ICO with one image
        width, height, _, _, planes, bits, length, offset = struct.unpack("<BBBBHHII", data[6:22])
        self.assertEqual((planes, bits, offset, length), (1, 32, 22, len(logo)))
        self.assertEqual(data[22:], logo)  # the official logo, not re-encoded
        png_width, png_height = struct.unpack(">II", logo[16:24])
        self.assertEqual((width, height), (png_width % 256, png_height % 256))
        # Google: square, at least 8x8, ideally a multiple of 48 px.
        self.assertEqual(png_width, png_height)
        self.assertEqual(png_width % 48, 0)
        self.assertNotIn(b"<html", data.lower())
        with self.assertRaises(ValueError):
            favicon_ico(b"<!DOCTYPE html><html></html>")
        with self.assertRaises(ValueError):
            favicon_ico(logo[:16] + struct.pack(">II", 192, 96) + logo[24:])

    def test_favicon_routing_never_falls_back_to_the_flutter_shell(self) -> None:
        production = (ROOT.parent / "infrastructure/nginx/default.conf").read_text(encoding="utf-8")
        local = (ROOT.parent / "infrastructure/nginx/local.conf").read_text(encoding="utf-8")
        for config in (production, local):
            # An exact-match location wins over the `location /` SPA fallback.
            self.assertRegex(
                config,
                r"location = /favicon\.ico \{\s*root /var/www/landing;\s*"
                r"try_files /favicon\.ico =404;\s*\}",
            )
        self.assertIn('/favicon.ico "public, max-age=86400";', production)
        flutter_web = ROOT.parent / "frontend/web"
        # The two web roots do not overlap: Flutter keeps favicon.png and its manifest icons.
        self.assertFalse((flutter_web / "favicon.ico").exists())
        self.assertTrue((flutter_web / "favicon.png").exists())
        manifest = json.loads((flutter_web / "manifest.json").read_text(encoding="utf-8"))
        for icon in manifest["icons"]:
            self.assertTrue((flutter_web / icon["src"]).exists(), icon["src"])
        robots = (OUT / "robots.txt").read_text(encoding="utf-8")
        self.assertNotIn("Disallow", robots)

    def test_images_are_bounded_and_local(self) -> None:
        logo = ROOT / "src/logo.png"
        self.assertLess(logo.stat().st_size, 50_000)
        for lang in CONTENT:
            card = (ROOT / f"src/social-{lang}.png").read_bytes()
            self.assertEqual(card[:8], b"\x89PNG\r\n\x1a\n")
            self.assertEqual(struct.unpack(">II", card[16:24]), (1200, 630))
        hero = (ROOT / "src/hero.svg").read_text(encoding="utf-8")
        self.assertNotIn("<script", hero)
        self.assertNotIn('href="http', hero)
        self.assertNotIn("url(http", hero)

    def test_integrated_routing_contract(self) -> None:
        production = (ROOT.parent / "infrastructure/nginx/default.conf").read_text(encoding="utf-8")
        local = (ROOT.parent / "infrastructure/nginx/local.conf").read_text(encoding="utf-8")
        for config in (production, local):
            for path in ("/", "/en/", "/uz/", "/robots.txt", "/sitemap.xml"):
                self.assertIn(f"location = {path} {{", config)
            self.assertIn("location ^~ /landing-assets/", config)
            self.assertRegex(config, r"location = /ru \{ return 301 /; \}")
            self.assertRegex(config, r"location = /ru/ \{ return 301 /; \}")
            self.assertNotRegex(config, r"location = /ru/ \{\s*root")
            self.assertRegex(config, r"location / \{\s*try_files \$uri \$uri/ /index.html;")
            self.assertIn("location /api/", config)
            self.assertIn("location /media/", config)
        for overlay in ("docker-compose.prod.yml", "docker-compose.local.yml"):
            self.assertIn("./website/dist:/var/www/landing:ro", (ROOT.parent / overlay).read_text(encoding="utf-8"))
        shell = (ROOT.parent / "frontend/web/index.html").read_text(encoding="utf-8")
        bootstrap = (ROOT.parent / "frontend/web/flutter_bootstrap.js").read_text(encoding="utf-8")
        self.assertIn('name="robots" content="noindex,follow"', shell)
        self.assertIn("retireLegacyFlutterServiceWorker", bootstrap)
        self.assertIn("flutter-first-frame", bootstrap)


if __name__ == "__main__":
    unittest.main()
