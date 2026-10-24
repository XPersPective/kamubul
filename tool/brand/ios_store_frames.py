"""Create App Store (iPhone 6.9") screenshots from real iOS simulator captures.

Usage: python tool/brand/ios_store_frames.py <capture-dir> <output-dir>
Captures come from .github/workflows/ios-screenshots.yml (store_capture_test).
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1320, 2868
FONT_BOLD = 'C:/Windows/Fonts/segoeuib.ttf'
FONT_REGULAR = 'C:/Windows/Fonts/segoeui.ttf'

# Store screenshots show product use only; iOS has no ads or purchases.
SHOTS = [
    ('02-ilanlar.png', '01-kamu-ilanlari.png', 'Kamu ilanları tek yerde',
     'Memur, işçi, sözleşmeli ve belediye ilanlarını inceleyin.', False),
    ('03-ilan-sartlari.png', '02-sartlar.png', 'Şartlar tek bakışta',
     'Kontenjanı, son başvuruyu, eğitimi ve puan türünü görün.', False),
    ('04-kadrolar.png', '03-kadrolar.png', 'Her ayrıntı düzenli',
     'Aranan nitelikleri ve başvuru bilgilerini kolayca okuyun.', False),
    ('01-asistan.png', '04-asistan.png', '“Bu ilan bana uygun mu?”',
     'İlanın şartlarını Asistan’a sorun, madde madde anlayın.', True),
    ('06-ayarlar.png', '05-hatirlatma.png', 'Son başvuruyu kaçırmayın',
     'Son başvuru hatırlatması ve yeni ilan bildirimi; tema ve yazı boyutu.', True),
]


def gradient(dark: bool) -> Image.Image:
    top, bottom = ((11, 21, 32), (23, 60, 83)) if dark else ((23, 101, 156), (14, 42, 61))
    base = Image.new('RGB', (W, H))
    draw = ImageDraw.Draw(base)
    for y in range(H):
        t = y / (H - 1)
        draw.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    glow = Image.new('L', (W, H), 0)
    ImageDraw.Draw(glow).ellipse((-320, -520, W + 320, 1000), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(200))
    return Image.composite(Image.new('RGB', (W, H), (255, 255, 255)), base, glow.point(lambda v: v // 3))


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new('L', image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *image.size), radius, fill=255)
    out = image.convert('RGBA')
    out.putalpha(mask)
    return out


def wrap(draw, text, font, width):
    lines, current = [], ''
    for word in text.split():
        trial = f'{current} {word}'.strip()
        if draw.textlength(trial, font=font) > width and current:
            lines.append(current)
            current = word
        else:
            current = trial
    return lines + ([current] if current else [])


def frame(raw: Path, title: str, subtitle: str, dark: bool) -> Image.Image:
    canvas = gradient(dark).convert('RGBA')
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.truetype(FONT_BOLD, 96)
    sub_font = ImageFont.truetype(FONT_REGULAR, 48)
    y = 150
    for line in wrap(draw, title, title_font, W - 140):
        draw.text(((W - draw.textlength(line, font=title_font)) / 2, y), line, font=title_font, fill='white')
        y += 116
    y += 18
    for line in wrap(draw, subtitle, sub_font, W - 200):
        draw.text(((W - draw.textlength(line, font=sub_font)) / 2, y), line, font=sub_font, fill=(220, 235, 248))
        y += 64
    shot = Image.open(raw).convert('RGB')
    top, bezel = y + 60, 22
    screen_h = H - top - 90 - 2 * bezel
    screen_w = min(round(shot.width * screen_h / shot.height), W - 220)
    shot = shot.resize((screen_w, round(shot.height * screen_w / shot.width)), Image.LANCZOS)
    shot = shot.crop((0, 0, screen_w, min(shot.height, screen_h)))
    device = rounded(Image.new('RGBA', (shot.width + 2 * bezel, shot.height + 2 * bezel), (12, 18, 26, 255)), 96)
    device.alpha_composite(rounded(shot, 76), (bezel, bezel))
    x = (W - device.width) // 2
    shadow = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x + 12, top + 36, x + device.width - 12, top + device.height + 36), 96, fill=(0, 0, 0, 110))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(44)))
    canvas.alpha_composite(device, (x, top))
    return canvas.convert('RGB')


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit('usage: ios_store_frames.py <capture-dir> <output-dir>')
    source, target = Path(sys.argv[1]), Path(sys.argv[2])
    missing = [raw for raw, *_ in SHOTS if not (source / raw).is_file()]
    if missing:
        raise SystemExit('missing simulator captures: ' + ', '.join(missing))
    target.mkdir(parents=True, exist_ok=True)
    for raw, name, title, subtitle, dark in SHOTS:
        frame(source / raw, title, subtitle, dark).save(target / name, optimize=True)
        print('ready', name)


if __name__ == '__main__':
    main()
