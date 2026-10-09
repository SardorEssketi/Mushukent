"""Focused checks of the generated public site and integration contract."""

from __future__ import annotations

import json
import struct
import unittest
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse

from build import CONTENT, OUT, ROOT, main


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
                page = OUT / ("index.html" if lang == "en" else f"{lang}/index.html")
                document = page.read_text(encoding="utf-8")
                parsed = Tags()
                parsed.feed(document)
                self.assertEqual(parsed.all("html")[0]["lang"], lang)
                self.assertEqual(len(parsed.all("h1")), 1)
                self.assertGreaterEqual(len(parsed.all("h2")), 5)
                self.assertIn(content["hero"], " ".join(parsed.text))
                self.assertIn(content["mission_body"], " ".join(parsed.text))
                self.assertNotIn("flutter_bootstrap.js", document)
                self.assertEqual(len(parsed.all("nav")), 3)

    def test_metadata_and_assets(self) -> None:
        for lang, content in CONTENT.items():
            with self.subTest(lang=lang):
                page = OUT / ("index.html" if lang == "en" else f"{lang}/index.html")
                document = page.read_text(encoding="utf-8")
                parsed = Tags()
                parsed.feed(document)
                canonical = next(a["href"] for a in parsed.all("link") if a.get("rel") == "canonical")
                self.assertEqual(canonical, "https://mushukistan.uz" + ("/" if lang == "en" else f"/{lang}/"))
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
                    self.assertTrue(href.startswith(("/", "#", "mailto:")), href)
                    if href.startswith("/"):
                        self.assertFalse(urlparse(href).netloc)
                self.assertIn('href="/privacy"', document)
                self.assertIn('href="/child-safety"', document)
                self.assertIn('href="/delete-account"', document)

    def test_sitemap_robots_and_manifest(self) -> None:
        sitemap = ET.parse(OUT / "sitemap.xml")
        locs = [e.text for e in sitemap.findall(".//{http://www.sitemaps.org/schemas/sitemap/0.9}loc")]
        self.assertEqual(locs, ["https://mushukistan.uz/", "https://mushukistan.uz/ru/", "https://mushukistan.uz/uz/"])
        robots = (OUT / "robots.txt").read_text(encoding="utf-8")
        self.assertIn("Allow: /", robots)
        self.assertIn("Sitemap: https://mushukistan.uz/sitemap.xml", robots)
        manifest = json.loads((ROOT.parent / "frontend/web/manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["start_url"], "/feed")
        self.assertEqual(manifest["scope"], "/")

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
            for path in ("/", "/ru/", "/uz/", "/robots.txt", "/sitemap.xml"):
                self.assertIn(f"location = {path} {{", config)
            self.assertIn("location ^~ /landing-assets/", config)
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
