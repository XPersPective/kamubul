"""Create App Store (iPhone 6.9") screenshots from real iOS simulator captures.

Usage: python tool/brand/ios_store_frames.py <capture-dir> <output-dir>
Captures come from .github/workflows/ios-screenshots.yml (store_capture_test).
Order and copy follow the researched Google Play set (docs/growth/STORE_COPY.md,
tool/brand/store_frames.py): Assistant first, one brand background for all.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1320, 2868
FONT_BOLD = 'C:/Windows/Fonts/segoeuib.ttf'
FONT_SEMI = 'C:/Windows/Fonts/seguisb.ttf'
FONT_REGULAR = 'C:/Windows/Fonts/segoeui.ttf'

# Store screenshots show product use; purchase and trial promotions are excluded.
SHOTS = [
    ('assistant.png', '01-asistan-bana-uygun-mu.png', 'İlanı Asistan’a sorun',
     'Yaş, eğitim ve KPSS şartlarını madde madde görün.'),
    ('home-light.png', '02-kamu-ilanlari-tek-yerde.png', 'Kamu ilanları tek yerde',
     'Memur, işçi, sözleşmeli ve belediye ilanlarını inceleyin.'),
    ('detail-summary.png', '03-sartlar-tek-bakista.png', 'Şartlar tek bakışta',
     'Kontenjanı, son başvuruyu, eğitimi ve puan türünü görün.'),
    ('detail-positions.png', '04-pozisyonlar-ayri-kartlarda.png', 'Her pozisyon ayrı kartta',
     'Kişi sayısı ve aranan nitelikler düzenli biçimde gösterilir.'),
    ('searches.png', '05-size-uygun-ilanlar.png', 'Size uyan ilanları bulun',
     'Şehir, eğitim, yaş, meslek ve puan kriterlerini seçin.'),
    ('detail-dark.png', '06-son-basvuruyu-kacirmayin.png', 'Son başvuruyu kaçırmayın',
     'Kalan gün rozetleri ve son başvuru hatırlatmasıyla takip edin.'),
    ('home-dark.png', '07-acik-ve-koyu-tema.png', 'Size uygun görünüm',
     'Açık ve koyu tema, ayarlanabilir yazı boyutu.'),
]

TOP, BOTTOM = (23, 101, 156), (12, 44, 66)


def background() -> Image.Image:
    base = Image.new('RGB', (W, H))
    draw = ImageDraw.Draw(base)
    for y in range(H):
        t = y / (H - 1)
        draw.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    glow = Image.new('L', (W, H), 0)
    ImageDraw.Draw(glow).ellipse((-360, -620, W + 360, 1100), fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(220))
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


def status_bar(shot: Image.Image) -> Image.Image:
    """In-app captures have no system bar; draw iPhone's 9:41 bar and island."""
    shot = shot.convert('RGB')
    draw = ImageDraw.Draw(shot)
    bg = shot.getpixel((shot.width // 2, 40))
    dark = sum(bg) / 3 < 128
    ink = (245, 247, 250) if dark else (17, 24, 39)
    s = shot.width / 1320
    island_w, island_h = 380 * s, 112 * s
    cx = shot.width / 2
    draw.rounded_rectangle((cx - island_w / 2, 34 * s, cx + island_w / 2, 34 * s + island_h), island_h / 2, fill=(0, 0, 0))
    font = ImageFont.truetype(FONT_SEMI, round(52 * s))
    draw.text((150 * s, 58 * s), '9:41', font=font, fill=ink)
    # Signal bars.
    x0, base = 940 * s, 120 * s
    for i in range(4):
        h = (14 + i * 9) * s
        draw.rounded_rectangle((x0 + i * 18 * s, base - h, x0 + i * 18 * s + 12 * s, base), 3 * s, fill=ink)
    # Wi-Fi arcs.
    wx, wy = 1050 * s, 124 * s
    for r in (42, 28, 14):
        draw.pieslice((wx - r * s, wy - r * s, wx + r * s, wy + r * s), 225, 315, fill=ink)
        if r > 14:
            inner = r - 7
            draw.pieslice((wx - inner * s, wy - inner * s, wx + inner * s, wy + inner * s), 225, 315, fill=bg)
    # Battery.
    bx, by = 1110 * s, 80 * s
    draw.rounded_rectangle((bx, by, bx + 76 * s, by + 38 * s), 10 * s, outline=ink, width=round(4 * s))
    draw.rounded_rectangle((bx + 7 * s, by + 7 * s, bx + 69 * s, by + 31 * s), 6 * s, fill=ink)
    draw.rounded_rectangle((bx + 80 * s, by + 12 * s, bx + 86 * s, by + 26 * s), 3 * s, fill=ink)
    return shot


def frame(raw: Path, title: str, subtitle: str) -> Image.Image:
    canvas = background().convert('RGBA')
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.truetype(FONT_BOLD, 104)
    sub_font = ImageFont.truetype(FONT_REGULAR, 50)
    y = 168
    for line in wrap(draw, title, title_font, W - 140):
        draw.text(((W - draw.textlength(line, font=title_font)) / 2, y), line, font=title_font, fill='white')
        y += 124
    y += 22
    for line in wrap(draw, subtitle, sub_font, W - 120):
        draw.text(((W - draw.textlength(line, font=sub_font)) / 2, y), line, font=sub_font, fill=(222, 236, 248))
        y += 68
    shot = status_bar(Image.open(raw))
    bezel = 26
    top = y + 70
    screen_h = H - top - 2 * bezel + 140  # device runs off the bottom edge
    screen_w = round(shot.width * screen_h / shot.height)
    if screen_w > W - 200:
        screen_w = W - 200
        screen_h = round(shot.height * screen_w / shot.width)
    shot = shot.resize((screen_w, screen_h), Image.LANCZOS)
    device = rounded(Image.new('RGBA', (screen_w + 2 * bezel, screen_h + 2 * bezel), (14, 20, 28, 255)), 118)
    device.alpha_composite(rounded(shot, 96), (bezel, bezel))
    x = (W - device.width) // 2
    shadow = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x + 16, top + 40, x + device.width - 16, top + device.height + 40), 118, fill=(0, 0, 0, 120))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(50)))
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
    for raw, name, title, subtitle in SHOTS:
        frame(source / raw, title, subtitle).save(target / name, optimize=True)
        print('ready', name)


if __name__ == '__main__':
    main()
