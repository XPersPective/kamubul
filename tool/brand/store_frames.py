"""Google Play ekran görüntüsü çerçeveleri: marka zemini, başlık ve cihaz içinde gerçek ekran.

Kullanım: python tool/brand/store_frames.py <ham-görüntü-klasörü> <çıktı-klasörü>
Ham klasörde SHOTS listesindeki adlarla 1080x2400 civarı emülatör görüntüleri bulunur.
home-light.png varsa aynı dille 1024x500 featureGraphic.png da üretilir.
Görüntüler gerçek uygulamadan alınır; metinler yalnız var olan özellikleri anlatır.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1080, 1920
FONT_BOLD = 'C:/Windows/Fonts/segoeuib.ttf'
FONT_REGULAR = 'C:/Windows/Fonts/segoeui.ttf'
ICON = Path(__file__).resolve().parents[2] / 'assets' / 'brand' / 'kamubul_icon.png'

# (ham dosya, çıktı adı, başlık, alt cümle, koyu zemin mi)
SHOTS = [
    ('home-light.png', '01-tum-kamu-ilanlari.png', 'Kamu ilanları\ntek yerde',
     'Memur, işçi, sözleşmeli personel ve belediye ilanları her gün güncel.', False),
    ('detail-summary.png', '02-sartlar-tek-bakista.png', 'Şartlar\ntek bakışta',
     'Kontenjan, son başvuru, eğitim, puan türü ve yaş en üstte özetlenir.', False),
    ('detail-positions.png', '03-her-pozisyon-ayri.png', 'Her pozisyon\nayrı kartta',
     'Kişi sayısı ve aranan nitelikler düzenli; tablolar okunur.', False),
    ('assistant.png', '04-bana-uygun-mu.png', 'Bu ilan\nbana uygun mu?',
     'KamuBul Asistan ilan metnini kriterlerinizle karşılaştırır.', False),
    ('searches.png', '05-size-uygun-ilanlar.png', 'Size uygun ilanlar\nöne çıksın',
     'Eğitim, yaş ve puan bilginizi kaydedin; uygun ilanlar en üstte.', False),
    ('home-dark.png', '06-koyu-tema.png', 'Gece de\ngöz yormaz',
     'Açık ve koyu tema, ayarlanabilir yazı boyutu.', True),
    ('detail-dark.png', '07-son-basvuruyu-kacirmayin.png', 'Son başvuruyu\nkaçırmayın',
     'Kalan gün rozetleri ve süreli ilanlarda tahmini son başvuru günü.', True),
    ('pro.png', '08-reklamsiz-deneyin.png', '7 gün\nreklamsız deneyin',
     'Pro ile reklamsız kullanım ve daha fazla Asistan hakkı.', False),
]


def gradient(dark: bool, w: int = W, h: int = H) -> Image.Image:
    top, bottom = ((0x0B, 0x15, 0x20), (0x17, 0x3C, 0x53)) if dark else ((0x17, 0x65, 0x9C), (0x0E, 0x2A, 0x3D))
    base = Image.new('RGB', (w, h))
    draw = ImageDraw.Draw(base)
    for y in range(h):
        t = y / (h - 1)
        draw.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    # Yumuşak ışık halkası: düz zeminden daha derinlikli bir yüzey.
    glow = Image.new('L', (w, h), 0)
    ImageDraw.Draw(glow).ellipse((-260, -420 * h // H, w + 260, 760 * h // H), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(160 * h // H or 1))
    return Image.composite(Image.new('RGB', (w, h), (255, 255, 255)), base, glow.point(lambda v: v // 3))


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new('L', image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *image.size), radius, fill=255)
    out = image.convert('RGBA')
    out.putalpha(mask)
    return out


def frame(raw: Path, title: str, subtitle: str, dark: bool) -> Image.Image:
    canvas = gradient(dark).convert('RGBA')
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.truetype(FONT_BOLD, 78)
    sub_font = ImageFont.truetype(FONT_REGULAR, 38)
    y = 96
    for line in title.split('\n'):
        w = draw.textlength(line, font=title_font)
        draw.text(((W - w) / 2, y), line, font=title_font, fill='white')
        y += 92
    y += 14
    words, lines, current = subtitle.split(), [], ''
    for word in words:
        trial = f'{current} {word}'.strip()
        if draw.textlength(trial, font=sub_font) > W - 180:
            lines.append(current)
            current = word
        else:
            current = trial
    lines.append(current)
    for line in lines:
        w = draw.textlength(line, font=sub_font)
        draw.text(((W - w) / 2, y), line, font=sub_font, fill=(220, 235, 248))
        y += 52
    # Cihaz: ince koyu çerçeve içinde gerçek ekran, altta gölge.
    shot = Image.open(raw).convert('RGB')
    top = y + 48
    screen_w, bezel = 760, 18
    # Uzun ekran görüntüsü tuvale sığacak kadar üstten gösterilir (cihaz alttan taşmaz).
    screen_h = min(round(shot.height * screen_w / shot.width), H - top - 70 - 2 * bezel)
    shot = shot.resize((screen_w, round(shot.height * screen_w / shot.width)), Image.LANCZOS).crop((0, 0, screen_w, screen_h))
    device = Image.new('RGBA', (screen_w + 2 * bezel, screen_h + 2 * bezel), (12, 18, 26, 255))
    device = rounded(device, 64)
    device.alpha_composite(rounded(shot, 48), (bezel, bezel))
    x = (W - device.width) // 2
    shadow = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x + 10, top + 30, x + device.width - 10, top + device.height + 30), 64, fill=(0, 0, 0, 110))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(36)))
    canvas.alpha_composite(device, (x, top))
    return canvas.convert('RGB')


def device(raw: Path, screen_w: int, screen_h: int, bezel: int, radius: int) -> Image.Image:
    """Gerçek ekranın üst kısmı ince koyu çerçeve içinde."""
    shot = Image.open(raw).convert('RGB')
    shot = shot.resize((screen_w, round(shot.height * screen_w / shot.width)), Image.LANCZOS).crop((0, 0, screen_w, screen_h))
    body = rounded(Image.new('RGBA', (screen_w + 2 * bezel, screen_h + 2 * bezel), (12, 18, 26, 255)), radius)
    body.alpha_composite(rounded(shot, radius - bezel), (bezel, bezel))
    return body


def feature_graphic(raw: Path) -> Image.Image:
    """Sade tanıtım görseli: marka zemini, simge, başlık; kurum adı/logosu ya da sınav markası yok."""
    fw, fh = 1024, 500
    canvas = gradient(False, fw, fh).convert('RGBA')
    draw = ImageDraw.Draw(canvas)
    icon = rounded(Image.open(ICON).convert('RGB').resize((84, 84), Image.LANCZOS), 22)
    canvas.alpha_composite(icon, (64, 64))
    draw.text((168, 76), 'KamuBul', font=ImageFont.truetype(FONT_BOLD, 44), fill='white')
    headline = ImageFont.truetype(FONT_BOLD, 62)
    for i, line in enumerate(('Kamu iş ilanları', 'tek yerde')):
        draw.text((64, 186 + i * 74), line, font=headline, fill='white')
    draw.text((66, 352), 'Memur · İşçi · Sözleşmeli · Belediye', font=ImageFont.truetype(FONT_REGULAR, 30), fill=(220, 235, 248))
    chip = ImageFont.truetype(FONT_BOLD, 22)
    x, layer = 66, Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    for label in ('Ücretsiz', 'Açık kaynak', 'Hesap gerektirmez'):
        w = draw.textlength(label, font=chip)
        ImageDraw.Draw(layer).rounded_rectangle((x, 410, x + w + 36, 452), 21, fill=(255, 255, 255, 38), outline=(255, 255, 255, 110), width=2)
        x += w + 52
    canvas.alpha_composite(layer)
    draw = ImageDraw.Draw(canvas)
    x = 66
    for label in ('Ücretsiz', 'Açık kaynak', 'Hesap gerektirmez'):
        draw.text((x + 18, 416), label, font=chip, fill='white')
        x += draw.textlength(label, font=chip) + 52
    # Sağda büyük, yarı saydam simge: telefon/kurum görüntüsü olmadan marka vurgusu.
    big = Image.open(ICON).convert('RGB').resize((300, 300), Image.LANCZOS)
    big = rounded(big, 76)
    big.putalpha(big.getchannel('A').point(lambda v: v * 92 // 100))
    shadow = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((680, 122, 980, 422), 76, fill=(0, 0, 0, 110))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(30)))
    canvas.alpha_composite(big, (670, 100))
    return canvas.convert('RGB')


def main() -> None:
    source, target = Path(sys.argv[1]), Path(sys.argv[2])
    target.mkdir(parents=True, exist_ok=True)
    for raw, name, title, subtitle, dark in SHOTS:
        if not (source / raw).is_file():
            print('eksik', raw)
            continue
        frame(source / raw, title, subtitle, dark).save(target / name, optimize=True)
        print('hazır', name)
    if (source / 'home-light.png').is_file():
        feature_graphic(source / 'home-light.png').save(target / 'featureGraphic.png', optimize=True)
        print('hazır featureGraphic.png')


if __name__ == '__main__':
    main()
