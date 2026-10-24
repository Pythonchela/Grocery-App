"""Generates every icon and store image for the two apps, so they stay consistent.

    python tools/make_brand_assets.py        (from marketplace_app/; needs Pillow)

Writes:
  android/app/src/<flavor>/res/...   launcher icons (adaptive + legacy) and their background colour
  store/<flavor>/                    Play Store icon (512), feature graphic (1024x500)
  ../public/                         the website's favicon and app icons (shopping brand)

The mark is "BX" in the display font on the brand's colours; the seller app adds a
SELLER tag so the two are told apart on one home screen. Change a colour or a name
here and run it again.
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)  # marketplace_app/
WEB = os.path.join(os.path.dirname(ROOT), 'public')
FONT = os.path.join(ROOT, 'assets', 'fonts', 'Outfit-ExtraBold.ttf')

INK = (17, 24, 39)        # tokens: primary / inverse
ACCENT = (26, 86, 255)    # tokens: accent
WHITE = (255, 255, 255)

APPS = {
    'shop': dict(
        name='BazaarX',
        tagline='Shop everything you love',
        background=ACCENT,
        tag=None,
        tag_color=None,
    ),
    'vendor': dict(
        name='BazaarX Seller',
        tagline='Run your shop from your phone',
        background=INK,
        tag='SELLER',
        tag_color=ACCENT,
    ),
}

SS = 4  # draw at 4x and scale down, for clean edges


def font(size):
    return ImageFont.truetype(FONT, int(size))


def hexcolor(rgb):
    return '#%02X%02X%02X' % rgb


def mark(size, app, *, rounded, safe=1.0, transparent_bg=False):
    """The icon at [size] px. [safe] shrinks the artwork toward the centre (adaptive
    icons are masked, so the artwork must sit inside the middle ~66%)."""
    s = size * SS
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if not transparent_bg:
        if rounded:
            d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.22), fill=app['background'] + (255,))
        else:
            d.rectangle([0, 0, s, s], fill=app['background'] + (255,))

    has_tag = app['tag'] is not None
    text_h = 0.46 * safe
    f = font(s * text_h)
    w = d.textlength('BX', font=f)
    top = s * ((0.10 if has_tag else 0.22) + (1 - safe) * 0.5)
    d.text(((s - w) / 2, top), 'BX', font=f, fill=WHITE + (255,))

    if has_tag:
        bx0, bx1 = s * (0.5 - 0.36 * safe), s * (0.5 + 0.36 * safe)
        by0 = s * (0.5 + 0.18 * safe)
        by1 = s * (0.5 + 0.36 * safe)
        d.rounded_rectangle([int(bx0), int(by0), int(bx1), int(by1)], radius=int(s * 0.05 * safe),
                            fill=app['tag_color'] + (255,))
        f2 = font(s * 0.115 * safe)
        w2 = d.textlength(app['tag'], font=f2)
        d.text(((s - w2) / 2, by0 + (by1 - by0) * 0.12), app['tag'], font=f2, fill=WHITE + (255,))

    return img.resize((size, size), Image.LANCZOS)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def android_icons(flavor, app):
    res = os.path.join(ROOT, 'android', 'app', 'src', flavor, 'res')
    for name, scale in DENSITIES.items():
        # Legacy icon (Android 7 and older): the rounded square itself, 48dp.
        save(mark(int(48 * scale), app, rounded=True), os.path.join(res, f'mipmap-{name}', 'ic_launcher.png'))
        # Adaptive foreground (Android 8+): 108dp, artwork kept inside the safe zone.
        save(mark(int(108 * scale), app, rounded=False, safe=0.62, transparent_bg=True),
             os.path.join(res, f'mipmap-{name}', 'ic_launcher_foreground.png'))

    adaptive = os.path.join(res, 'mipmap-anydpi-v26', 'ic_launcher.xml')
    os.makedirs(os.path.dirname(adaptive), exist_ok=True)
    with open(adaptive, 'w', newline='\n') as fh:
        fh.write('<?xml version="1.0" encoding="utf-8"?>\n'
                 '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                 '    <background android:drawable="@color/ic_launcher_background"/>\n'
                 '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                 '</adaptive-icon>\n')

    colors = os.path.join(res, 'values', 'ic_launcher_background.xml')
    os.makedirs(os.path.dirname(colors), exist_ok=True)
    with open(colors, 'w', newline='\n') as fh:
        fh.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
                 f'    <color name="ic_launcher_background">{hexcolor(app["background"])}</color>\n'
                 '</resources>\n')


def store_images(flavor, app):
    out = os.path.join(ROOT, 'store', flavor)
    # Play Store icon: 512x512, square (Google applies its own mask).
    save(mark(512, app, rounded=False), os.path.join(out, 'icon-512.png'))

    # Feature graphic: 1024x500.
    w, h = 1024 * SS, 500 * SS
    img = Image.new('RGB', (w, h), app['background'])
    d = ImageDraw.Draw(img)
    # a soft band of the opposite colour along the bottom, so it is not a flat slab
    band = ACCENT if app['background'] == INK else INK
    d.rectangle([0, int(h * 0.86), w, h], fill=band)

    tile = 300 * SS
    icon = mark(300, app, rounded=True).resize((tile, tile), Image.LANCZOS)
    tx, ty = int(w * 0.07), int(h * 0.5 - tile / 2)
    # A thin light edge, so the tile reads against a background of its own colour.
    d.rounded_rectangle([tx - 6 * SS, ty - 6 * SS, tx + tile + 6 * SS, ty + tile + 6 * SS],
                        radius=int(tile * 0.22) + 6 * SS, outline=(255, 255, 255), width=3 * SS)
    img.paste(icon, (tx, ty), icon)

    # The name is sized to fit the room beside the tile, never cut off.
    x = tx + tile + int(w * 0.05)
    room = w - x - int(w * 0.04)
    size = h * 0.20
    while d.textlength(app['name'], font=font(size)) > room:
        size *= 0.95
    d.text((x, int(h * 0.26)), app['name'], font=font(size), fill=WHITE)
    sub = h * 0.085
    while d.textlength(app['tagline'], font=font(sub)) > room:
        sub *= 0.95
    d.text((x, int(h * 0.56)), app['tagline'], font=font(sub), fill=(220, 228, 255) if app['background'] == ACCENT else (200, 208, 224))
    save(img.resize((1024, 500), Image.LANCZOS), os.path.join(out, 'feature-graphic-1024x500.png'))


def notification_icon():
    """The small white icon in the notification shade (Android draws it as a mask)."""
    path = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res', 'drawable', 'ic_notification.xml')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', newline='\n') as fh:
        fh.write('<?xml version="1.0" encoding="utf-8"?>\n'
                 '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
                 '    android:width="24dp" android:height="24dp"\n'
                 '    android:viewportWidth="24" android:viewportHeight="24">\n'
                 '    <!-- A shopping bag: body filled, handle stroked. -->\n'
                 '    <path android:fillColor="#FFFFFFFF" android:pathData="M5,8h14l1,13H4L5,8z"/>\n'
                 '    <path android:strokeColor="#FFFFFFFF" android:strokeWidth="2" android:strokeLineCap="round"\n'
                 '        android:pathData="M8.5,8V7a3.5,3.5 0,0 1,7 0V8"/>\n'
                 '</vector>\n')


def website_icons():
    app = APPS['shop']
    save(mark(512, app, rounded=False, safe=0.8), os.path.join(WEB, 'icon-512x512.png'))
    save(mark(192, app, rounded=False, safe=0.8), os.path.join(WEB, 'icon-192x192.png'))
    save(mark(180, app, rounded=False), os.path.join(WEB, 'apple-touch-icon.png'))
    ico = mark(256, app, rounded=True)
    ico.save(os.path.join(WEB, 'favicon.ico'), sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])


if __name__ == '__main__':
    for flavor, app in APPS.items():
        android_icons(flavor, app)
        store_images(flavor, app)
    notification_icon()
    website_icons()
    print('done')
