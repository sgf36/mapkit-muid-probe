"""Generate graded synthetic reel frames to find where OCR breaks.

Not a substitute for real screenshots — it characterises the failure boundary so
real screenshots only have to tell us where on that curve reels actually sit.

Five difficulty tiers, each carrying realistic reel chrome (handle, caption,
hashtags, music line, counts) so the noise problem is exercised too.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import random, os, json

random.seed(20260816)

W, H = 720, 1280
OUT = os.path.join(os.path.dirname(__file__), "..", "fixtures")
os.makedirs(OUT, exist_ok=True)

F = "C:/Windows/Fonts/"
def font(name, size):
    return ImageFont.truetype(F + name, size)

PLACES = [
    ("DA ENZO AL 29",            "da-enzo-al-29"),
    ("Sant'Eustachio Il Caffè",  "sant-eustachio"),
    ("Otaleg Trastevere",        "otaleg"),
    ("Bonci Pizzarium",          "bonci-pizzarium"),
    ("Roscioli Salumeria",       "roscioli"),
]

# --- background ---------------------------------------------------------

# Warm, limited palette: plates, sauces, wood, dark interior. OCR difficulty is
# driven by edge statistics, so this mixes soft depth-of-field blobs with a few
# genuinely sharp edges and specular highlights, the way a real frame does.
PALETTE = [
    (188, 92, 48), (214, 138, 62), (152, 42, 34), (238, 214, 176),
    (108, 76, 44), (86, 96, 52), (232, 176, 106), (64, 44, 34),
    (198, 170, 122), (142, 116, 74),
]

def food_background(seed):
    rnd = random.Random(seed)
    base = rnd.choice([(46, 32, 24), (34, 28, 26), (58, 42, 30)])
    img = Image.new("RGB", (W, H), base)
    d = ImageDraw.Draw(img)

    # large out-of-focus masses
    for _ in range(26):
        x, y = rnd.randint(-160, W), rnd.randint(-160, H)
        rx, ry = rnd.randint(160, 460), rnd.randint(160, 460)
        d.ellipse([x, y, x + rx, y + ry], fill=rnd.choice(PALETTE))
    img = img.filter(ImageFilter.GaussianBlur(rnd.randint(14, 26)))

    # mid-depth elements, lightly blurred
    mid = Image.new("RGB", (W, H)); mid.paste(img)
    dm = ImageDraw.Draw(mid)
    for _ in range(14):
        x, y = rnd.randint(-60, W), rnd.randint(160, H - 160)
        rx, ry = rnd.randint(90, 260), rnd.randint(70, 200)
        dm.ellipse([x, y, x + rx, y + ry], fill=rnd.choice(PALETTE))
    mid = mid.filter(ImageFilter.GaussianBlur(5))
    img = Image.blend(img, mid, 0.75)

    # sharp foreground detail — cutlery edges, plate rims, table lines
    d = ImageDraw.Draw(img)
    for _ in range(9):
        x, y = rnd.randint(0, W), rnd.randint(120, H - 120)
        L = rnd.randint(120, 400)
        wdt = rnd.randint(2, 7)
        c = rnd.choice([(236, 232, 224), (30, 22, 18), (206, 186, 150)])
        d.line([x, y, x + rnd.randint(-L, L), y + rnd.randint(-90, 90)], fill=c, width=wdt)
    for _ in range(5):
        x, y = rnd.randint(0, W), rnd.randint(120, H - 120)
        r = rnd.randint(70, 210)
        d.arc([x, y, x + r, y + r], rnd.randint(0, 180), rnd.randint(200, 360),
              fill=(238, 231, 218), width=rnd.randint(2, 5))

    # specular highlights
    hi = Image.new("RGB", (W, H), (0, 0, 0))
    dh = ImageDraw.Draw(hi)
    for _ in range(16):
        x, y = rnd.randint(0, W), rnd.randint(0, H)
        r = rnd.randint(8, 46)
        dh.ellipse([x, y, x + r, y + r], fill=(255, 244, 224))
    img = Image.blend(img, hi.filter(ImageFilter.GaussianBlur(12)), 0.22)

    # vignette
    vig = Image.new("L", (W, H), 0)
    dv = ImageDraw.Draw(vig)
    dv.ellipse([-W // 3, -H // 6, W + W // 3, H + H // 6], fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(160))
    img = Image.composite(img, Image.new("RGB", (W, H), base), vig)

    # sensor grain
    px = img.load()
    for _ in range(30000):
        x, y = rnd.randint(0, W - 1), rnd.randint(0, H - 1)
        r, g, b = px[x, y]
        n = rnd.randint(-20, 20)
        px[x, y] = (max(0,min(255,r+n)), max(0,min(255,g+n)), max(0,min(255,b+n)))
    return img

def outlined(d, xy, text, fnt, fill, stroke, w):
    d.text(xy, text, font=fnt, fill=fill, stroke_width=w, stroke_fill=stroke)

def chrome(img):
    """Instagram UI furniture — the noise a real screenshot carries."""
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle([0, H - 260, W, H], fill=(0, 0, 0, 90))
    small = font("arialbd.ttf", 21)
    tiny  = font("calibrib.ttf", 19)
    d.ellipse([24, H - 232, 60, H - 196], fill=(190, 150, 110))
    d.text((72, H - 228), "@romefoodguide", font=small, fill=(255, 255, 255))
    d.text((246, H - 228), "· Follow", font=small, fill=(200, 200, 200))
    d.text((24, H - 178), "5 places you HAVE to eat at in Rome", font=tiny, fill=(240, 240, 240))
    d.text((24, H - 148), "#rome #romefood #italy #pasta #travelreels", font=tiny, fill=(175, 195, 235))
    d.text((24, H - 108), "original audio · romefoodguide", font=tiny, fill=(215, 215, 215))
    for i, n in enumerate(["12.4K", "318", "1,204"]):
        d.text((W - 92, 300 + i * 96), n, font=tiny, fill=(255, 255, 255))
    d.text((24, 42), "Reels", font=font("arialbd.ttf", 26), fill=(255, 255, 255))

def tier1_clean(img, name):                       # caption bar, maximum legibility
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle([0, 470, W, 620], fill=(0, 0, 0, 205))
    f = font("ariblk.ttf", 44)
    d.text((40, 505), name, font=f, fill=(255, 255, 255))
    return img

def tier2_outlined(img, name):                    # white on stroke, over video
    d = ImageDraw.Draw(img)
    f = font("ariblk.ttf", 46)
    outlined(d, (40, 500), name, f, (255, 255, 255), (0, 0, 0), 5)
    return img

def tier3_shadow_busy(img, name):                 # drop shadow only, busy plate
    d = ImageDraw.Draw(img, "RGBA")
    f = font("impact.ttf", 52)
    d.text((44, 506), name, font=f, fill=(0, 0, 0, 150))
    d.text((40, 500), name, font=f, fill=(255, 255, 255))
    return img

def tier4_low_contrast(img, name):                # tonal text, no stroke
    d = ImageDraw.Draw(img)
    f = font("seguibl.ttf", 40)
    d.text((40, 500), name, font=f, fill=(214, 202, 186))
    return img

def tier5_motion(img, name):                      # mid-transition frame
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    f = font("ariblk.ttf", 46)
    outlined(d, (40, 500), name, f, (255, 255, 255, 235), (0, 0, 0, 235), 4)
    layer = layer.rotate(-2.4, resample=Image.BICUBIC, center=(W // 2, 520))
    layer = layer.filter(ImageFilter.GaussianBlur(2.4))
    img.paste(layer, (0, 0), layer)
    return img

TIERS = [
    ("t1-clean",        tier1_clean,       "solid caption bar, heavy face"),
    ("t2-outlined",     tier2_outlined,    "white with black stroke over video"),
    ("t3-shadow-busy",  tier3_shadow_busy, "drop shadow only, high-frequency background"),
    ("t4-low-contrast", tier4_low_contrast,"tonal text, no stroke or shadow"),
    ("t5-motion",       tier5_motion,      "rotated and motion-blurred mid-transition"),
]

manifest = []
for ti, (tname, fn, desc) in enumerate(TIERS):
    for pi, (place, slug) in enumerate(PLACES):
        img = food_background(seed=1000 + ti * 17 + pi)
        img = fn(img, place)
        chrome(img)
        fname = f"{tname}__{slug}.jpg"
        img.save(os.path.join(OUT, fname), "JPEG", quality=85)
        manifest.append({"file": fname, "tier": tname, "tier_desc": desc,
                         "expected": place})

with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)

print(f"wrote {len(manifest)} fixtures to {os.path.abspath(OUT)}")
for t, _, d in TIERS:
    print(f"  {t:16s} {d}")
