"""Crop and redact the reviewed Android captures; never copy originals to dist.

Usage: python website/tool/prepare_screenshots.py --input .data/private-screenshots
Requires Pillow 11.2.1. Coordinates are in the ORIGINAL 1080 x 2436 images.
Unexpected input bytes fail closed because a changed capture needs a new review.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src/screenshots"
CROP = (0, 104, 1080, 2316)  # Android bars only; all five app tabs remain.
WIDTHS = (270, 540)
SOURCES = {
    "map": "586438c8470269f1b4e397b5bd868b6f1047a6955c6cca3b99d864eb7934e3df",
    "feed": "5c9b8e7463aead80596e4cb6ade8ccd05c17788526051f3e09900384da5c59e9",
    "leaderboard": "b94d93fabfe4f5fb74e0b0fb81aef167d710c4b9e1faa6c5fabdf3e6f82f2906",
    "profile": "b903d1950a698dff001c8dd82965e4eb61ee039b15e397908d1567f5740ede57",
}

# Opaque covers, not blur: identities cannot be reconstructed from these outputs.
# A quiet bar explicitly indicates redaction; no fictional names/users are added.
TEXT = {
    "profile": [((350, 378, 1000, 465), "#ffffff", 330),
                ((350, 486, 1000, 553), "#ffffff", 390)],
    "leaderboard": [((354, 621, 1000, 680), "#ffdad0", 365),
                    ((354, 837, 1000, 900), "#fffcf7", 265),
                    ((354, 1053, 1000, 1120), "#fffcf7", 290)],
    "feed": [((240, 327, 1000, 384), "#ffffff", 370),
             ((240, 1697, 1000, 1752), "#ffffff", 255)],
}
AVATARS = {
    "profile": [((90, 371, 314, 590), "#ffdad0")],
    "leaderboard": [((220, 623, 331, 735), "#e8ded4"),
                    ((220, 839, 332, 951), "#dcebd6"),
                    ((220, 1052, 332, 1166), "#dcebd6")],
    "feed": [((93, 325, 211, 444), "#e8ded4"),
             ((93, 1686, 211, 1812), "#ffdad0")],
}


def sanitize(name: str, source: Image.Image) -> Image.Image:
    image = source.convert("RGB")
    image.info.clear()
    draw = ImageDraw.Draw(image)
    for box, surface, length in TEXT.get(name, []):
        draw.rectangle(box, fill=surface)
        left, top, right, bottom = box
        middle = (top + bottom) // 2
        draw.rounded_rectangle((left + 8, middle - 10, left + 8 + length, middle + 10),
                               radius=10, fill="#c7c1b8")
    for box, color in AVATARS.get(name, []):
        draw.ellipse(box, fill=color)
    if name == "feed":
        # The owner confirmed rights to the first kitten photo on 2026-10-12.
        # No rights were established for the partial second post photograph.
        draw.rectangle((228, 1843, 852, 2075), fill="#e8ded4")
    image = image.crop(CROP)
    image.info.clear()
    return image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    args = parser.parse_args()
    # Validate ALL sources before writing any public derivative.
    originals = {}
    for name, expected in SOURCES.items():
        path = args.input / f"{name}.jpg"
        assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, f"Unreviewed capture: {name}"
        with Image.open(path) as source:
            assert source.size == (1080, 2436), f"Unexpected dimensions: {name}"
            originals[name] = sanitize(name, source)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    variants = {}
    for name, image in originals.items():
        for width in WIDTHS:
            size = (width, CROP[3] - CROP[1])
            height = size[1] * width // 1080  # both sizes preserve the exact ratio
            resized = image.resize((width, height), Image.Resampling.LANCZOS)
            for extension in ("webp", "jpg"):
                file = OUTPUT / f"app-{name}-{width}.{extension}"
                if extension == "webp":
                    resized.save(file, "WEBP", quality=84, method=6)
                else:
                    resized.save(file, "JPEG", quality=85, optimize=True, progressive=True)
                variants[file.name] = {"width": width, "height": height,
                                       "sha256": hashlib.sha256(file.read_bytes()).hexdigest()}
    (OUTPUT / "publication.json").write_text(json.dumps({
        "recipe_version": 1, "crop": list(CROP), "source_size": [1080, 2436],
        "publication_review": "Owner confirmed first feed photo rights on 2026-10-12. Second photo and all account identities concealed. City-level public service map only.",
        "source_sha256": SOURCES, "variants": variants,
    }, indent=2) + "\n", encoding="utf-8")
    print(f"Prepared {len(variants)} metadata-free, reviewed derivatives in {OUTPUT}")


if __name__ == "__main__":
    main()
