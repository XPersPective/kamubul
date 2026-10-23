"""Create Google Play screenshots from real Turkish app captures.

Usage: python tool/brand/store_frames.py <raw-screenshot-dir> <output-dir>
The raw directory must contain the exact SHOTS filenames.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1080, 1920
FONT_BOLD = 'C:/Windows/Fonts/segoeuib.ttf'
FONT_REGULAR = 'C:/Windows/Fonts/segoeui.ttf'

# Store screenshots show product use; purchase and trial promotions are excluded.
SHOTS = [
    ('assistant.png', '01-asistan-bana-uygun-mu.png', 'İlanı Asistan’a sorun',
     'Yaş, eğitim ve KPSS şartlarını madde madde görün.', False),
    ('home-light.png', '02-kamu-ilanlari-tek-yerde.png', 'Kamu ilanları tek yerde',
     'Memur, işçi, sözleşmeli ve belediye ilanlarını inceleyin.', False),
    ('detail-summary.png', '03-sartlar-tek-bakista.png', 'Şartlar tek bakışta',
     'Kontenjanı, son başvuruyu, eğitimi ve puan türünü görün.', False),
    ('detail-positions.png', '04-pozisyonlar-ayri-kartlarda.png', 'Her pozisyon ayrı kartta',
     'Kişi sayısı ve aranan nitelikler düzenli biçimde gösterilir.', False),
    ('searches.png', '05-size-uygun-ilanlar.png', 'Size uyan ilanları bulun',
     'Şehir, eğitim, yaş, meslek ve puan kriterlerini seçin.', False),
    ('detail-dark.png', '06-son-basvuruyu-kacirmayin.png', 'Son başvuruyu kaçırmayın',
     'Kalan gün rozetleriyle başvuru tarihini takip edin.', True),
    ('home-dark.png', '07-acik-ve-koyu-tema.png', 'Size uygun görünüm',
     'Açık ve koyu tema, ayarlanabilir yazı boyutu.', True),
]


def gradient(dark: bool) -> Image.Image:
    top, bottom = ((11, 21, 32), (23, 60, 83)) if dark else ((23, 101, 156), (14, 42, 61))
    base = Image.new('RGB', (W, H))
    draw = ImageDraw.Draw(base)
    for y in range(H):
        t = y / (H - 1)
        draw.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    glow = Image.new('L', (W, H), 0)
    ImageDraw.Draw(glow).ellipse((-260, -420, W + 260, 760), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    return Image.composite(Image.new('RGB', (W, H), (255, 255, 255)), base, glow.point(lambda v: v // 3))


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new('L', image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *image.size), radius, fill=255)
    out = image.convert('RGBA')
    out.putalpha(mask)
    return out


def frame(raw: Path, title: str, subtitle: str, dark: bool) -> Image.Image:
    canvas = gradient(dark).convert('RGBA')
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.truetype(FONT_BOLD, 76)
    sub_font = ImageFont.truetype(FONT_REGULAR, 38)
    y = 100
    words = title.split()
    lines, current = [], ''
    for word in words:
        trial = f'{current} {word}'.strip()
        if draw.textlength(trial, font=title_font) > W - 100:
            lines.append(current)
            current = word
        else:
            current = trial
    if current:
        lines.append(current)
    for line in lines:
        x = (W - draw.textlength(line, font=title_font)) / 2
        draw.text((x, y), line, font=title_font, fill='white')
        y += 92
    y += 12
    words, lines, current = subtitle.split(), [], ''
    for word in words:
        trial = f'{current} {word}'.strip()
        if draw.textlength(trial, font=sub_font) > W - 150:
            lines.append(current)
            current = word
        else:
            current = trial
    if current:
        lines.append(current)
    for line in lines:
        x = (W - draw.textlength(line, font=sub_font)) / 2
        draw.text((x, y), line, font=sub_font, fill=(220, 235, 248))
        y += 52
    shot = Image.open(raw).convert('RGB')
    top, screen_w, bezel = y + 42, 760, 18
    screen_h = min(round(shot.height * screen_w / shot.width), H - top - 70 - 2 * bezel)
    shot = shot.resize((screen_w, round(shot.height * screen_w / shot.width)), Image.LANCZOS).crop((0, 0, screen_w, screen_h))
    device = rounded(Image.new('RGBA', (screen_w + 2 * bezel, screen_h + 2 * bezel), (12, 18, 26, 255)), 64)
    device.alpha_composite(rounded(shot, 48), (bezel, bezel))
    x = (W - device.width) // 2
    shadow = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x + 10, top + 30, x + device.width - 10, top + device.height + 30), 64, fill=(0, 0, 0, 110))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(36)))
    canvas.alpha_composite(device, (x, top))
    return canvas.convert('RGB')


def feature_graphic() -> Image.Image:
    """Neutral brand graphic; avoid logos/claims implying government affiliation."""
    fw, fh = 1024, 500
    top, bottom = (23, 101, 156), (14, 42, 61)
    canvas = Image.new('RGB', (fw, fh))
    draw = ImageDraw.Draw(canvas)
    for y in range(fh):
        t = y / (fh - 1)
        draw.line([(0, y), (fw, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    draw.text((58, 60), 'KamuBul', font=ImageFont.truetype(FONT_BOLD, 40), fill='white')
    title = ImageFont.truetype(FONT_BOLD, 58)
    draw.text((58, 174), 'İlanı Asistan’a sorun.', font=title, fill='white')
    draw.text((62, 258), 'Şartları madde madde görün.', font=ImageFont.truetype(FONT_REGULAR, 34), fill=(220, 235, 248))
    # Simple neutral document-and-magnifier illustration, not an official seal or symbol.
    draw.rounded_rectangle((756, 92, 910, 300), 22, outline=(235, 245, 252), width=8)
    draw.line((790, 147, 868, 147), fill=(235, 245, 252), width=8)
    draw.line((790, 178, 850, 178), fill=(235, 245, 252), width=8)
    draw.line((790, 209, 840, 209), fill=(235, 245, 252), width=8)
    draw.ellipse((830, 222, 916, 308), outline=(235, 245, 252), width=9)
    draw.line((898, 293, 951, 346), fill=(235, 245, 252), width=11)
    draw.text((62, 422), 'Bağımsız kamu ilanı takip uygulaması', font=ImageFont.truetype(FONT_REGULAR, 21), fill=(220, 235, 248))
    return canvas


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit('usage: store_frames.py <raw-screenshot-dir> <output-dir>')
    source, target = Path(sys.argv[1]), Path(sys.argv[2])
    missing = [raw for raw, *_ in SHOTS if not (source / raw).is_file()]
    if missing:
        raise SystemExit('missing real app screenshots: ' + ', '.join(missing))
    target.mkdir(parents=True, exist_ok=True)
    for raw, name, title, subtitle, dark in SHOTS:
        frame(source / raw, title, subtitle, dark).save(target / name, optimize=True)
        print('ready', name)
    feature_graphic().save(target / 'featureGraphic.png', optimize=True)
    print('ready featureGraphic.png')


if __name__ == '__main__':
    main()
