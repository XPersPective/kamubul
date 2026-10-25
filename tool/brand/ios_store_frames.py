"""Create App Store (iPhone 6.9") and Google Play screenshots from real captures.

Usage: python tool/brand/ios_store_frames.py <capture-dir> <output-dir> [--android]
--android: 1080x1920 Play set from Android emulator captures (android-screenshots.yml).
Captures come from .github/workflows/ios-screenshots.yml (store_capture_test).
Order and copy follow the researched Google Play set (docs/growth/STORE_COPY.md,
tool/brand/store_frames.py): Assistant first, one brand background for all.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1320, 2868
ANDROID = False
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
    ImageDraw.Draw(glow).ellipse((-360 * W / 1320, -620 * H / 2868, W + 360 * W / 1320, 1100 * H / 2868), fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(220 * W / 1320))
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


def android_status_bar(shot: Image.Image) -> Image.Image:
    """In-app captures have no system bar; draw Android's bar and camera hole."""
    shot = shot.convert('RGB')
    draw = ImageDraw.Draw(shot)
    bg = shot.getpixel((shot.width // 2, 30))
    ink = (245, 247, 250) if sum(bg) / 3 < 128 else (17, 24, 39)
    s = shot.width / 1080
    draw.ellipse((shot.width / 2 - 22 * s, 26 * s, shot.width / 2 + 22 * s, 70 * s), fill=(0, 0, 0))
    draw.text((56 * s, 22 * s), '9:41', font=ImageFont.truetype(FONT_SEMI, round(40 * s)), fill=ink)
    x0, base = 850 * s, 70 * s
    for i in range(4):
        h = (12 + i * 7) * s
        draw.rectangle((x0 + i * 13 * s, base - h, x0 + i * 13 * s + 8 * s, base), fill=ink)
    wx, wy = 945 * s, 72 * s
    draw.pieslice((wx - 32 * s, wy - 32 * s, wx + 32 * s, wy + 32 * s), 225, 315, fill=ink)
    bx, by = 985 * s, 38 * s
    draw.rounded_rectangle((bx, by, bx + 22 * s, by + 38 * s), 4 * s, fill=ink)
    return shot


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
    k = W / 1320  # iPhone düzeni Play ölçüsüne orantılı küçülür
    # Sabit düzen: başlık tek satıra sığar, alt başlık en çok iki satır; telefonlar
    # bütün görsellerde aynı hizada başlar.
    size = round(104 * k)
    while size > 70 * k and draw.textlength(title, font=ImageFont.truetype(FONT_BOLD, size)) > W - 120 * k:
        size -= 2
    title_font = ImageFont.truetype(FONT_BOLD, size)
    sub_font = ImageFont.truetype(FONT_REGULAR, round(50 * k))
    top_y = 168 * k
    draw.text(((W - draw.textlength(title, font=title_font)) / 2, top_y + (104 * k - size) / 2), title, font=title_font, fill='white')
    lines = wrap(draw, subtitle, sub_font, W - 160 * k)[:2]
    y = top_y + (124 + 22) * k + (68 * k if len(lines) == 1 else 0) / 2
    for line in lines:
        draw.text(((W - draw.textlength(line, font=sub_font)) / 2, y), line, font=sub_font, fill=(222, 236, 248))
        y += 68 * k
    y = top_y + (124 + 22 + 2 * 68) * k
    shot = (android_status_bar if ANDROID else status_bar)(Image.open(raw))
    bezel = round(26 * k)
    top = round(y + 70 * k)
    screen_h = round(H - top - 2 * bezel + 140 * k)  # device runs off the bottom edge
    screen_w = round(shot.width * screen_h / shot.height)
    if screen_w > W - 200 * k:
        screen_w = round(W - 200 * k)
        screen_h = round(shot.height * screen_w / shot.width)
    shot = shot.resize((screen_w, screen_h), Image.LANCZOS)
    outer, inner = round((80 if ANDROID else 118) * k), round((60 if ANDROID else 96) * k)
    device = rounded(Image.new('RGBA', (screen_w + 2 * bezel, screen_h + 2 * bezel), (14, 20, 28, 255)), outer)
    device.alpha_composite(rounded(shot, inner), (bezel, bezel))
    x = (W - device.width) // 2
    shadow = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x + 16 * k, top + 40 * k, x + device.width - 16 * k, top + device.height + 40 * k), outer, fill=(0, 0, 0, 120))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(50 * k)))
    canvas.alpha_composite(device, (x, top))
    return canvas.convert('RGB')


def main() -> None:
    global W, H, ANDROID
    args = [a for a in sys.argv[1:] if a != '--android']
    if len(args) != 2:
        raise SystemExit('usage: ios_store_frames.py <capture-dir> <output-dir> [--android]')
    if '--android' in sys.argv:
        W, H, ANDROID = 1080, 1920, True
    source, target = Path(args[0]), Path(args[1])
    missing = [raw for raw, *_ in SHOTS if not (source / raw).is_file()]
    if missing:
        raise SystemExit('missing simulator captures: ' + ', '.join(missing))
    target.mkdir(parents=True, exist_ok=True)
    for raw, name, title, subtitle in SHOTS:
        frame(source / raw, title, subtitle).save(target / name, optimize=True)
        print('ready', name)


if __name__ == '__main__':
    main()
