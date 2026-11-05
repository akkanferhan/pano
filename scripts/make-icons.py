import json, os, sys, math
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

root = sys.argv[1]
A = os.path.join(root, "Pano/Assets.xcassets")
B = os.path.join(A, "App Icon & Top Shelf Image.brandassets")
INFO = {"author": "xcode", "version": 1}
FONT = "/System/Library/Fonts/SFNSRounded.ttf"
SS = 2  # süper örnekleme

VIOLET = (124, 58, 237); PINK = (236, 72, 153); BLUE = (59, 130, 246); CYAN = (34, 211, 238); INDIGO = (91, 91, 255)

def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    try: f.set_variation_by_name(weight)
    except Exception: pass
    return f

def lin_grad(w, h, c1, c2, angle=135):
    """Doğrusal gradyan (RGBA)."""
    a = math.radians(angle)
    dx, dy = math.cos(a), math.sin(a)
    g = Image.new("RGBA", (w, h))
    px = g.load()
    L = abs(w * dx) + abs(h * dy)
    for y in range(h):
        for x in range(w):
            t = ((x * dx + y * dy) - min(0, w * dx) - min(0, h * dy)) / L
            t = max(0, min(1, t))
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)) + (255,)
    return g

def grad_fast(w, h, c1, c2, angle=135):
    # küçük çizip büyüt (hızlı)
    sw, sh = max(2, w // 8), max(2, h // 8)
    return lin_grad(sw, sh, c1, c2, angle).resize((w, h), Image.BICUBIC)

def blob(img, cx, cy, r, color, alpha, blur):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (alpha,))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    img.alpha_composite(layer)

def back(w, h):
    img = Image.new("RGBA", (w, h), (9, 9, 22, 255))
    s = min(w, h)
    blob(img, 0.15 * w, 0.10 * h, 0.62 * s, VIOLET, 255, 0.28 * s)
    blob(img, 0.92 * w, 0.95 * h, 0.66 * s, PINK, 235, 0.30 * s)
    blob(img, 0.62 * w, -0.05 * h, 0.45 * s, BLUE, 200, 0.26 * s)
    blob(img, 0.05 * w, 1.00 * h, 0.40 * s, CYAN, 120, 0.25 * s)
    # hafif vinyet
    v = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(v).rectangle([0, 0, w, h], outline=(0, 0, 0, 90), width=int(0.06 * s))
    img.alpha_composite(v.filter(ImageFilter.GaussianBlur(0.08 * s)))
    return img

def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m

def glass_pane(pw, ph, strength=1.0, content=True):
    r = int(ph * 0.11)
    pane = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    base = Image.new("RGBA", (pw, ph), (255, 255, 255, int(34 * strength)))
    hi = grad_fast(pw, ph, (255, 255, 255), (255, 255, 255), 90)
    hi_alpha = Image.linear_gradient("L").resize((pw, ph)).point(lambda v: int((255 - v) * 0.22 * strength))
    hi.putalpha(hi_alpha)
    base.alpha_composite(hi)
    mask = rounded_mask((pw, ph), r)
    pane.paste(base, (0, 0), mask)
    d = ImageDraw.Draw(pane)
    bw = max(2, int(pw * 0.006))
    d.rounded_rectangle([bw // 2, bw // 2, pw - 1 - bw // 2, ph - 1 - bw // 2], radius=r, outline=(255, 255, 255, int(120 * strength)), width=bw)
    if not content:
        return pane
    pad = int(pw * 0.06)
    # üst çubuk: 3 nokta + adres kapsülü
    dot = int(ph * 0.035)
    ty = int(ph * 0.11)
    for i in range(3):
        cx = pad + dot + i * dot * 3
        d.ellipse([cx - dot, ty - dot, cx + dot, ty + dot], fill=(255, 255, 255, 120))
    ax0 = pad + dot * 10; ax1 = pw - pad
    d.rounded_rectangle([ax0, ty - dot * 1.4, ax1, ty + dot * 1.4], radius=dot * 1.4, fill=(255, 255, 255, 60))
    # medya kartı (oynat simgeli)
    my0 = int(ph * 0.25); mx1 = int(pw * 0.55); my1 = int(ph * 0.84)
    card = grad_fast(mx1 - pad, my1 - my0, VIOLET, PINK, 30)
    card.putalpha(rounded_mask(card.size, int(ph * 0.06)).point(lambda v: int(v * 0.92)))
    pane.alpha_composite(card, (pad, my0))
    cx, cy = (pad + mx1) / 2, (my0 + my1) / 2
    t = (my1 - my0) * 0.17
    d.polygon([(cx - t * 0.7, cy - t), (cx - t * 0.7, cy + t), (cx + t * 1.0, cy)], fill=(255, 255, 255, 240))
    # metin satırları
    lx = int(pw * 0.61)
    for i, frac in enumerate([0.9, 0.7, 0.82, 0.55]):
        y = my0 + int(ph * 0.03) + i * int(ph * 0.14)
        lw = int((pw - pad - lx) * frac)
        d.rounded_rectangle([lx, y, lx + lw, y + int(ph * 0.055)], radius=int(ph * 0.03), fill=(255, 255, 255, 70 if i == 0 else 45))
    return pane

def middle(w, h, cx=0.47, cy=0.5, scale=1.0):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    s = min(w, h)
    pw, ph = int(1.02 * s * scale * (w / h if w / h < 1.8 else 1.67)), int(0.62 * s * scale)
    pw = int(ph * 1.6)
    # arkadaki ikinci cam
    back_pane = glass_pane(int(pw * 0.92), int(ph * 0.92), 0.55, content=False)
    img.alpha_composite(back_pane, (int(cx * w - pw / 2 + pw * 0.14), int(cy * h - ph / 2 - ph * 0.16)))
    # gölge
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([cx * w - pw / 2, cy * h - ph / 2 + ph * 0.06, cx * w + pw / 2, cy * h + ph / 2 + ph * 0.06],
                                         radius=int(ph * 0.11), fill=(10, 0, 30, 120))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(ph * 0.08)))
    img.alpha_composite(glass_pane(pw, ph), (int(cx * w - pw / 2), int(cy * h - ph / 2)))
    return img

def pointer(w, h, px=0.72, py=0.72, scale=1.0):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    s = min(w, h) * scale
    x, y = px * w, py * h
    R = 0.105 * s
    blob(img, x, y, R * 1.9, PINK, 170, R * 0.9)
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([x - R, y - R + R * 0.25, x + R, y + R + R * 0.25], fill=(20, 0, 40, 150))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(R * 0.35)))
    d = ImageDraw.Draw(img)
    d.ellipse([x - R, y - R, x + R, y + R], fill=(255, 255, 255, 250))
    r2 = R * 0.46
    dot = grad_fast(int(r2 * 2) + 2, int(r2 * 2) + 2, VIOLET, PINK, 135)
    m = Image.new("L", dot.size, 0)
    ImageDraw.Draw(m).ellipse([0, 0, dot.size[0] - 1, dot.size[1] - 1], fill=255)
    dot.putalpha(m)
    img.alpha_composite(dot, (int(x - r2), int(y - r2)))
    return img

def render(fn, w, h):
    big = fn(w * SS, h * SS)
    return big.resize((w, h), Image.LANCZOS)

def wj(path, obj):
    os.makedirs(path, exist_ok=True)
    json.dump(obj, open(os.path.join(path, "Contents.json"), "w"), indent=2)

def imageset(path, files):
    os.makedirs(path, exist_ok=True)
    for f in os.listdir(path):
        if f.endswith(".png"): os.remove(os.path.join(path, f))
    imgs = []
    for scale, (name, im) in files.items():
        im.save(os.path.join(path, name))
        imgs.append({"filename": name, "idiom": "tv", "scale": scale})
    wj(path, {"images": imgs, "info": INFO})

def stack(name, sizes):
    sp = os.path.join(B, name + ".imagestack")
    if os.path.isdir(sp):
        import shutil; shutil.rmtree(sp)
    layers = [("Front", lambda w, h: pointer(w, h)), ("Middle", lambda w, h: middle(w, h)), ("Back", back)]
    wj(sp, {"info": INFO, "layers": [{"filename": f"{n}.imagestacklayer"} for n, _ in layers]})
    for n, fn in layers:
        lp = os.path.join(sp, n + ".imagestacklayer")
        wj(lp, {"info": INFO})
        files = {}
        for scale, (w, h) in sizes.items():
            im = render(fn, w, h)
            if n == "Back": im = im.convert("RGB")
            files[scale] = (f"{n.lower()}{scale}.png", im)
        imageset(os.path.join(lp, "Content.imageset"), files)

def shelf(w, h):
    """Top Shelf: tvOS tam ekran gösterirken yanları kırpar (yalnızca ortadaki 16:9 bölge görünür:
    1920x720'de orta ~%67, 2320x720'de orta ~%55). Bu yüzden yazı ve görsel ortada toplanır."""
    img = back(w, h)
    safe = (h * 16 / 9) / w            # görünen genişlik oranı
    left = 0.5 - safe / 2 + 0.04       # güvenli bölgenin sol kenarı (+pay)
    img.alpha_composite(middle(w, h, cx=0.5 + safe * 0.20, cy=0.52, scale=0.78))
    img.alpha_composite(pointer(w, h, px=0.5 + safe * 0.33, py=0.70, scale=0.8))
    d = ImageDraw.Draw(img)
    big = font(int(h * 0.22), "Bold")
    small = font(int(h * 0.062), "Medium")
    x = int(w * left)
    d.text((x, int(h * 0.27)), "Pano", font=big, fill=(255, 255, 255, 255))
    d.text((x + int(h * 0.008), int(h * 0.56)), "Apple TV için", font=small, fill=(255, 255, 255, 200))
    d.text((x + int(h * 0.008), int(h * 0.65)), "kişisel tarayıcı", font=small, fill=(255, 255, 255, 200))
    return img

def topshelf(name, sizes):
    files = {}
    for scale, (w, h) in sizes.items():
        files[scale] = (f"shelf{scale}.png", render(shelf, w, h).convert("RGB"))
    imageset(os.path.join(B, name + ".imageset"), files)

stack("App Icon", {"1x": (400, 240), "2x": (800, 480)})
stack("App Icon - App Store", {"1x": (1280, 768)})
topshelf("Top Shelf Image", {"1x": (1920, 720), "2x": (3840, 1440)})
topshelf("Top Shelf Image Wide", {"1x": (2320, 720), "2x": (4640, 1440)})

# Önizleme: katmanlar birleşik
prev = render(back, 800, 480)
prev.alpha_composite(render(lambda w, h: middle(w, h), 800, 480))
prev.alpha_composite(render(lambda w, h: pointer(w, h), 800, 480))
prev.convert("RGB").save(sys.argv[2])
print("ok")
