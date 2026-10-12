"""Release regressions for authentic, private-by-default screenshot publication."""

import hashlib
import json
import unittest
from pathlib import Path

from PIL import Image

from build import CONTENT, OUT, ROOT, main
from test_site import Tags


class ShowcaseTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        main()

    def test_all_reviewed_derivatives_are_bounded_and_metadata_free(self):
        source = ROOT / "src/screenshots"
        review = json.loads((source / "publication.json").read_text())
        self.assertEqual(len(review["variants"]), 16)
        self.assertEqual({p.name for p in source.iterdir()}, set(review["variants"]) | {"publication.json"})
        for name, info in review["variants"].items():
            with self.subTest(name=name):
                file = source / name
                self.assertEqual(hashlib.sha256(file.read_bytes()).hexdigest(), info["sha256"])
                self.assertNotIn(info["sha256"], review["source_sha256"].values())
                self.assertLess(file.stat().st_size, 160_000)
                with Image.open(file) as image:
                    self.assertEqual(image.size, (info["width"], info["height"]))
                    self.assertEqual(image.width * 1106, image.height * 540)
                    self.assertFalse(image.getexif())
                    self.assertNotIn("icc_profile", image.info)
                    # The app navigation ends on a white surface, not Android's black bar.
                    self.assertGreater(sum(image.convert("RGB").getpixel((image.width // 2, image.height - 3))), 700)

    def test_identity_regions_and_unapproved_photo_are_opaque(self):
        # Inner rectangles within the full-size covers, expressed after 1/2 resize
        # and the 104px status crop. Text/photo detail must not survive encoding.
        patches = {
            "profile": [(200, 157, 330, 161), (190, 204, 350, 208), (70, 179, 126, 196)],
            "feed": [(130, 124, 299, 127), (130, 809, 225, 812),
                     (63, 126, 89, 153), (64, 813, 87, 835), (150, 900, 390, 960)],
            "leaderboard": [(195, 271, 338, 276), (195, 380, 295, 384), (190, 489, 315, 493)],
        }
        for name, regions in patches.items():
            with Image.open(ROOT / f"src/screenshots/app-{name}-540.webp") as image:
                for box in regions:
                    patch = image.convert("RGB").crop(box)
                    for low, high in patch.getextrema():
                        self.assertLessEqual(high - low, 8, (name, box))  # lossy WebP quantization

    def test_localized_showcase_is_complete_without_javascript(self):
        for lang, content in CONTENT.items():
            with self.subTest(lang=lang):
                page = OUT / ("index.html" if lang == "en" else f"{lang}/index.html")
                document = page.read_text(encoding="utf-8")
                parsed = Tags()
                parsed.feed(document)
                self.assertLess(document.index('id="about"'), document.index('id="showcase"'))
                self.assertLess(document.index('id="showcase"'), document.index('id="how"'))
                self.assertIn(content["showcase_title"], " ".join(parsed.text))
                self.assertIn(content["showcase_note"], " ".join(parsed.text))
                images = [p for p in parsed.all("img") if "app-" in p["src"]]
                self.assertEqual(len(images), 4)
                self.assertEqual(len(parsed.all("picture")), 4)
                for image, (name, title, caption, alt) in zip(images, content["screens"]):
                    self.assertIn(f"app-{name}-540", image["src"])
                    self.assertEqual(image["alt"], alt)
                    self.assertEqual((image["width"], image["height"]), ("540", "1106"))
                    self.assertEqual(image["loading"], "lazy")
                    self.assertEqual(image["decoding"], "async")
                    self.assertIn("270w", image["srcset"])
                    self.assertIn("540w", image["srcset"])
                    self.assertIn(title, " ".join(parsed.text))
                    self.assertIn(caption, " ".join(parsed.text))
                for source in parsed.all("source"):
                    self.assertEqual(source["type"], "image/webp")
                    for variant in source["srcset"].split(", "):
                        self.assertTrue((OUT / variant.split()[0].lstrip("/")).is_file())
                gallery = next(p for p in parsed.all("ol") if p.get("class") == "showcase-gallery")
                self.assertEqual(gallery["tabindex"], "0")
                self.assertEqual(gallery["aria-label"], content["showcase_label"])
                self.assertEqual(gallery["aria-describedby"], "showcase-hint")
                self.assertEqual(len([p for p in parsed.all("article") if p.get("class") == "feature"]), 6)

    def test_private_sources_cannot_enter_generated_site(self):
        review = json.loads((ROOT / "src/screenshots/publication.json").read_text())
        public = list(OUT.rglob("*"))
        images = [p for p in public if p.is_file() and p.name.startswith("app-")]
        self.assertEqual(len(images), 16)
        for file in public:
            self.assertNotIn("original", file.name)
            self.assertNotIn("private", file.name)
            self.assertNotEqual(file.name, "publication.json")
            if file.is_file():
                self.assertNotIn(hashlib.sha256(file.read_bytes()).hexdigest(), review["source_sha256"].values())


if __name__ == "__main__":
    unittest.main()
