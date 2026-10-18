"""Regenerate the checked-in social card (optional; requires Pillow)."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
fonts = Path("C:/Windows/Fonts")
serif = fonts / "georgia.ttf"
sans = fonts / "arial.ttf"
messages = {
    "en": ("A better world", "for cats starts", "with us.", "CATS · LOST PETS · COMMUNITY · UZBEKISTAN"),
    "ru": ("Лучший мир", "для кошек", "начинается с нас.", "КОШКИ · ПОТЕРЯВШИЕСЯ ПИТОМЦЫ · УЗБЕКИСТАН"),
    "uz": ("Mushuklar uchun", "yaxshiroq dunyo", "bizdan boshlanadi.", "MUSHUKLAR · YO‘QOLGAN HAYVONLAR · O‘ZBEKISTON"),
}
icon = Image.open(root.parent / "frontend/assets/app_icon.png").convert("RGBA")
icon.resize((192, 192), Image.Resampling.LANCZOS).save(root / "src/logo.png", optimize=True)
icon.thumbnail((318, 318), Image.Resampling.LANCZOS)
for lang, lines in messages.items():
    canvas = Image.new("RGB", (1200, 630), "#fff8f0")
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((0, 0, 20, 630), fill="#c95f45")
    draw.rounded_rectangle((817, 65, 1143, 552), radius=38, fill="#e7eee5")
    canvas.paste(icon, (821, 147), icon)
    draw.text((80, 80), "Mushukistan.", font=ImageFont.truetype(serif, 53), fill="#2c2724")
    for index, line in enumerate(lines[:3]):
        draw.text((80, 225 + index * 91), line, font=ImageFont.truetype(serif, 67), fill="#2c2724")
    draw.text((84, 545), lines[3], font=ImageFont.truetype(sans, 18), fill="#716861")
    canvas.save(root / f"src/social-{lang}.png", optimize=True)
