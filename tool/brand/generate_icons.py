#!/usr/bin/env python3
"""Tek kaynak ikondan bütün platform ikonlarını üretir.

ORTAK_UYGULAMA_STANDARDI.md 4: Android uyarlanabilir ikon + Android 13
temalı (monochrome) ikon, splash görselleri, iOS ikonları (opak) ve web
ikonları. Pillow (MIT) gerekir.

Örnek:
  python tool/brand/generate_icons.py \
      --source brand/icon_1024.png \
      --app-root examples/core_only \
      --background "#0B3D66"
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

ANDROID_DENSITIES = {
    "mdpi": 1.0,
    "hdpi": 1.5,
    "xhdpi": 2.0,
    "xxhdpi": 3.0,
    "xxxhdpi": 4.0,
}
LEGACY_LAUNCHER_DP = 48  # ic_launcher.png taban boyutu
ADAPTIVE_CANVAS_DP = 108  # uyarlanabilir ikon tuvali
SPLASH_ICON_DP = 288  # splash'te ikonun kapladığı tuval

IOS_SIZES = [  # (px, kimlik soneki, ölçek)
    (20, "20x20", "1x"), (40, "20x20", "2x"), (60, "20x20", "3x"),
    (29, "29x29", "1x"), (58, "29x29", "2x"), (87, "29x29", "3x"),
    (40, "40x40", "1x"), (80, "40x40", "2x"), (120, "40x40", "3x"),
    (120, "60x60", "2x"), (180, "60x60", "3x"),
    (76, "76x76", "1x"), (152, "76x76", "2x"), (167, "83.5x83.5", "2x"),
    (1024, "1024x1024", "1x"),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path,
                        help="kaynak ikon (kare, en az 1024px)")
    parser.add_argument("--app-root", required=True, type=Path,
                        help="Flutter projesinin kökü (android/, ios/, web/)")
    parser.add_argument("--background", default="#0B3D66",
                        help="uzuv/arka plan rengi (#RRGGBB)")
    return parser.parse_args()


def load_source(path: Path) -> Image.Image:
    image = Image.open(path)
    if image.width != image.height:
        raise SystemExit(f"kaynak ikon kare olmalı: {image.size}")
    if image.width < 512:
        raise SystemExit(f"kaynak ikon en az 512px olmalı: {image.width}")
    return image.convert("RGBA")


def scale_to(source: Image.Image, size: int) -> Image.Image:
    return source.resize((size, size), Image.LANCZOS)


def write_png(image: Image.Image, path: Path, *, opaque: bool = False,
              background: tuple[int, int, int] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    out = image
    if opaque and background is not None:
        canvas = Image.new("RGB", image.size, background)
        canvas.paste(image, (0, 0), image if image.mode == "RGBA" else None)
        out = canvas
    out.save(path, "PNG")


def adaptive_foreground(source: Image.Image, size: int) -> Image.Image:
    """Kaynağı 108dp tuvalin güvenli bölgesine (~%66) yerleştirir."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inner = round(size * 66 / 108)
    glyph = scale_to(source, inner)
    offset = (size - inner) // 2
    canvas.paste(glyph, (offset, offset), glyph)
    return canvas


def monochrome(source: Image.Image, size: int) -> Image.Image:
    """Kaynağın siluetini düz renkli maskmeye çevirir (Android 13 teması)."""
    canvas = adaptive_foreground(source, size)
    alpha = canvas.getchannel("A")
    if alpha.getextrema() == (255, 255):  # kaynağı opak: dairesel siluet
        mask = Image.new("L", (size, size), 0)
        from PIL import ImageDraw

        inner = round(size * 66 / 108)
        ImageDraw.Draw(mask).ellipse(
            ((size - inner) // 2, (size - inner) // 2,
             (size + inner) // 2, (size + inner) // 2), fill=255)
        alpha = mask
    glyph = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    glyph.putalpha(alpha)
    return glyph


def circular(source: Image.Image, size: int) -> Image.Image:
    from PIL import ImageDraw

    scaled = scale_to(source, size)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(scaled, (0, 0), mask)
    return out


def splash_canvas(source: Image.Image, size: int,
                  background: tuple[int, int, int]) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), background + (255,))
    inner = round(size * SPLASH_ICON_DP / ADAPTIVE_CANVAS_DP)
    if inner > size:
        inner = size
    glyph = scale_to(source, inner)
    offset = (size - inner) // 2
    canvas.paste(glyph, (offset, offset), glyph)
    return canvas


def generate_android(source: Image.Image, app_root: Path,
                     background: tuple[int, int, int]) -> None:
    res = app_root / "android" / "app" / "src" / "main" / "res"
    for density, factor in ANDROID_DENSITIES.items():
        folder = res / f"mipmap-{density}"

        # Eski sürüm launcher ikonları
        legacy = round(LEGACY_LAUNCHER_DP * factor)
        write_png(scale_to(source, legacy), folder / "ic_launcher.png")
        write_png(circular(source, legacy), folder / "ic_launcher_round.png")

        # Uyarlanabilir ikon ön planı + monochrome (aynı tuval)
        canvas_size = round(ADAPTIVE_CANVAS_DP * factor)
        write_png(adaptive_foreground(source, canvas_size),
                  folder / "ic_launcher_foreground.png")
        write_png(monochrome(source, canvas_size),
                  folder / "ic_launcher_monochrome.png")

        # Splash görseli
        write_png(splash_canvas(source, round(ADAPTIVE_CANVAS_DP * factor),
                                background),
                  res / f"drawable-{density}" / "splash.png")

    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    adaptive_xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        '</adaptive-icon>\n'
    )
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        (anydpi / name).write_text(adaptive_xml, encoding="utf-8")

    values = res / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        '    <color name="ic_launcher_background">#%02X%02X%02X</color>\n'
        % background
        + "</resources>\n",
        encoding="utf-8",
    )


def generate_ios(source: Image.Image, app_root: Path,
                 background: tuple[int, int, int]) -> None:
    iconset = (app_root / "ios" / "Runner" / "Assets.xcassets"
               / "AppIcon.appiconset")
    iconset.mkdir(parents=True, exist_ok=True)
    entries = []
    for px, idiom, scale in IOS_SIZES:
        name = f"AppIcon-{px}.png"
        write_png(scale_to(source, px), iconset / name, opaque=True,
                  background=background)
        entries.append({
            "filename": name,
            "idiom": "iphone" if idiom.startswith(("20x20", "29x29", "40x40",
                                                   "60x60")) else "ipad",
            "scale": scale,
            "size": idiom,
        })
    # 1024 pazarlama ikonu App Store'dur; idiom'u özel işaretle
    for entry in entries:
        if entry["filename"] == "AppIcon-1024.png":
            entry["idiom"] = "ios-marketing"
    contents = {"images": entries, "info": {
        "author": "napp_kit tool/brand",
        "version": 1,
    }}
    (iconset / "Contents.json").write_text(
        json.dumps(contents, indent=2) + "\n", encoding="utf-8")


def generate_web(source: Image.Image, app_root: Path,
                 background: tuple[int, int, int]) -> None:
    web = app_root / "web"
    if not web.exists():
        return
    write_png(scale_to(source, 16), web / "favicon.png")
    icons = web / "icons"
    for px in (192, 512):
        write_png(scale_to(source, px), icons / f"Icon-{px}.png",
                  opaque=True, background=background)
        # maskable: içerik güvenli bölgede küçültülür
        canvas = Image.new("RGBA", (px, px), background + (255,))
        inner = round(px * 0.8)
        glyph = scale_to(source, inner)
        canvas.paste(glyph, ((px - inner) // 2, (px - inner) // 2), glyph)
        write_png(canvas, icons / f"Icon-maskable-{px}.png")


def main() -> int:
    args = parse_args()
    background = tuple(
        int(args.background.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)
    )
    source = load_source(args.source)
    generate_android(source, args.app_root, background)
    generate_ios(source, args.app_root, background)
    generate_web(source, args.app_root, background)
    print("ikonlar üretildi:", args.app_root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
