"""Draws the six profile pictures offered in the profile editor
(assets/avatars/<name>.png, 256 x 256, full bleed: the app rounds them).
Run from the repository root: python3 tool/make_avatars.py

Flat shapes in the colours of the brand, big enough to read at 32 px in the
top bar. The names match `profileAvatars` in lib/ui/profiles.dart."""
import math
import os

from PIL import Image, ImageDraw

SIZE = 256
SS = 4  # supersampling for smooth edges
BIG = SIZE * SS

INK = (26, 21, 3)  # #1A1503, the dark of the initials
CREAM = (243, 238, 232)  # #F3EEE8
ACCENT = (255, 90, 54)  # #FF5A36
STRIPE = (184, 58, 29)  # #B83A1D
YELLOW = (232, 197, 71)  # #E8C547
TEAL = (111, 183, 168)  # #6FB7A8
BLUE = (127, 166, 255)  # #7FA6FF
PURPLE = (192, 139, 240)  # #C08BF0
ROSE = (238, 154, 174)  # #EE9AAE
CHEEK = (255, 128, 128, 110)


def shade(c, k):
    """Lighter (k > 0) or darker (k < 0) version of an RGB colour."""
    if k >= 0:
        return tuple(round(v + (255 - v) * k) for v in c[:3])
    return tuple(round(v * (1 + k)) for v in c[:3])


def u(v):
    """Design units (0..256) to supersampled pixels."""
    return v * SS


def box(cx, cy, rx, ry):
    return (u(cx - rx), u(cy - ry), u(cx + rx), u(cy + ry))


def pts(*xy):
    return [(u(x), u(y)) for x, y in xy]


def canvas(bg):
    img = Image.new("RGBA", (BIG, BIG), bg + (255,))
    d = ImageDraw.Draw(img)
    # Soft halo behind the character.
    d.ellipse(box(128, 120, 112, 112), fill=shade(bg, 0.12))
    return img, d


def overlay(img):
    """A transparent layer to draw see-through shapes on."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    return layer, ImageDraw.Draw(layer)


def line(d, xy, width, fill):
    """Polyline with round caps and joints."""
    p = pts(*xy)
    d.line(p, fill=fill, width=round(u(width)), joint="curve")
    r = u(width) / 2
    for x, y in (p[0], p[-1]):
        d.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def arc(d, cx, cy, rx, ry, start, end, width, fill):
    """Arc with round caps (angles in degrees, clockwise from 3 o'clock)."""
    d.arc(box(cx, cy, rx, ry), start, end, fill=fill, width=round(u(width)))
    r = u(width) / 2
    for a in (start, end):
        t = math.radians(a)
        # The stroke sits inside the bounding box: its middle is r inwards.
        x = u(cx) + (u(rx) - r) * math.cos(t)
        y = u(cy) + (u(ry) - r) * math.sin(t)
        d.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def eye(d, cx, cy, r, color=INK):
    """Round eye with a highlight."""
    d.ellipse(box(cx, cy, r, r * 1.12), fill=color)
    d.ellipse(box(cx + r * 0.32, cy - r * 0.38, r * 0.34, r * 0.34), fill=(255, 255, 255))


def cheeks(img, left, right, y, rx=12, ry=7):
    layer, d = overlay(img)
    d.ellipse(box(left, y, rx, ry), fill=CHEEK)
    d.ellipse(box(right, y, rx, ry), fill=CHEEK)
    img.alpha_composite(layer)


def ground(img, bg, cx, cy, rx, ry):
    layer, d = overlay(img)
    d.ellipse(box(cx, cy, rx, ry), fill=shade(bg, -0.22) + (150,))
    img.alpha_composite(layer)


def popcorn():
    bg = YELLOW
    img, d = canvas(bg)
    ground(img, bg, 128, 236, 64, 9)
    # Popcorn above the rim.
    puffs = [
        (84, 92, 22), (110, 76, 24), (140, 74, 25), (168, 90, 22),
        (72, 116, 20), (98, 104, 22), (128, 98, 24), (158, 106, 22), (186, 118, 18),
    ]
    for x, y, r in puffs:
        d.ellipse(box(x + 3, y + 4, r, r), fill=shade(YELLOW, -0.18))
    for x, y, r in puffs:
        d.ellipse(box(x, y, r, r), fill=CREAM)
        d.ellipse(box(x - r * 0.3, y - r * 0.3, r * 0.35, r * 0.3), fill=(255, 252, 246))
    # The tub: red and cream stripes, clipped to a trapezoid.
    tub = pts((62, 122), (194, 122), (176, 236), (80, 236))
    stripes = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(stripes)
    for i in range(-2, 10):
        x0 = 54 + i * 26
        sd.polygon(pts((x0, 110), (x0 + 13, 110), (x0 + 13 + 2, 240), (x0 + 2, 240)), fill=ACCENT if i % 2 == 0 else CREAM)
        sd.polygon(pts((x0 + 13, 110), (x0 + 26, 110), (x0 + 28, 240), (x0 + 15, 240)), fill=CREAM if i % 2 == 0 else ACCENT)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(tub, fill=255)
    img.paste(stripes, (0, 0), mask)
    d = ImageDraw.Draw(img)
    # Rim.
    d.rounded_rectangle((u(56), u(116), u(200), u(134)), radius=u(7), fill=STRIPE)
    # Face, on a cream label.
    d.rounded_rectangle((u(88), u(148), u(168), u(216)), radius=u(20), fill=CREAM, outline=STRIPE, width=u(4))
    eye(d, 110, 174, 8)
    eye(d, 146, 174, 8)
    arc(d, 128, 186, 14, 12, 20, 160, 5, INK)
    cheeks(img, 100, 156, 194, 7, 4)
    return img


def clap():
    bg = ACCENT
    img, d = canvas(bg)
    ground(img, bg, 128, 230, 82, 10)
    dark = (31, 27, 24)
    # Board.
    d.rounded_rectangle((u(48), u(100), u(208), u(226)), radius=u(16), fill=dark)
    # Hinged clapper, slightly open, with diagonal stripes.
    bar = Image.new("RGBA", (u(170), u(34)), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bar)
    bd.rounded_rectangle((0, 0, u(170) - 1, u(34) - 1), radius=u(8), fill=dark)
    for i in range(8):
        x = u(8 + i * 24)
        bd.polygon([(x, u(5)), (x + u(12), u(5)), (x + u(4), u(29)), (x - u(8), u(29))], fill=CREAM)
    bar = bar.rotate(14, resample=Image.BICUBIC, expand=True)
    img.alpha_composite(bar, (u(40), u(46)))
    d = ImageDraw.Draw(img)
    # Hinge.
    d.ellipse(box(56, 100, 9, 9), fill=STRIPE)
    # Stripes on the board top.
    d.rectangle((u(48), u(104), u(208), u(126)), fill=dark)
    for i in range(7):
        x = 50 + i * 24
        d.polygon(pts((x + 8, 106), (x + 20, 106), (x + 12, 124), (x, 124)), fill=CREAM)
    d.rounded_rectangle((u(48), u(100), u(208), u(130)), radius=u(8), outline=dark, width=u(4))
    # Face.
    eye(d, 104, 166, 12, CREAM)
    d.ellipse(box(104, 168, 6, 7), fill=INK)
    d.ellipse(box(106, 165, 2.4, 2.4), fill=(255, 255, 255))
    eye(d, 152, 166, 12, CREAM)
    d.ellipse(box(152, 168, 6, 7), fill=INK)
    d.ellipse(box(154, 165, 2.4, 2.4), fill=(255, 255, 255))
    arc(d, 128, 186, 18, 16, 15, 165, 6, CREAM)
    cheeks(img, 84, 172, 192, 9, 5)
    return img


def cat():
    bg = BLUE
    img, d = canvas(bg)
    fur = (44, 40, 56)
    inner = (238, 140, 160)
    # Ears.
    d.polygon(pts((46, 118), (62, 34), (116, 82)), fill=fur)
    d.polygon(pts((210, 118), (194, 34), (140, 82)), fill=fur)
    d.polygon(pts((62, 104), (68, 56), (100, 84)), fill=inner)
    d.polygon(pts((194, 104), (188, 56), (156, 84)), fill=inner)
    # Head and chest.
    d.ellipse(box(128, 266, 96, 60), fill=fur)
    d.ellipse(box(128, 140, 92, 80), fill=fur)
    # Eyes: yellow with slit pupils.
    for x in (92, 164):
        d.ellipse(box(x, 132, 19, 21), fill=YELLOW)
        d.ellipse(box(x, 132, 5.5, 16), fill=INK)
        d.ellipse(box(x + 6, 124, 4, 4), fill=(255, 255, 255))
    # Nose and mouth.
    d.polygon(pts((118, 162), (138, 162), (128, 173)), fill=inner)
    arc(d, 118, 172, 10, 9, 10, 150, 3.6, CREAM)
    arc(d, 138, 172, 10, 9, 30, 170, 3.6, CREAM)
    # Whiskers.
    for side in (-1, 1):
        for dy, tilt in ((0, -5), (11, 4)):
            x0 = 128 + side * 40
            line(d, [(x0, 168 + dy), (x0 + side * 46, 168 + dy + tilt)], 2.6, shade(CREAM, -0.08))
    return img


def fox():
    bg = TEAL
    img, d = canvas(bg)
    fur = (247, 120, 52)
    dark = (60, 34, 24)
    # Ears with dark tips.
    d.polygon(pts((40, 124), (56, 30), (112, 82)), fill=fur)
    d.polygon(pts((216, 124), (200, 30), (144, 82)), fill=fur)
    d.polygon(pts((50, 70), (56, 30), (78, 52)), fill=dark)
    d.polygon(pts((206, 70), (200, 30), (178, 52)), fill=dark)
    d.polygon(pts((58, 108), (64, 62), (96, 86)), fill=shade(fur, -0.25))
    d.polygon(pts((198, 108), (192, 62), (160, 86)), fill=shade(fur, -0.25))
    # Chest.
    d.ellipse(box(128, 270, 84, 60), fill=CREAM)
    # Head: wide cheeks, pointed muzzle.
    d.polygon(pts((30, 128), (64, 76), (192, 76), (226, 128), (184, 176), (128, 214), (72, 176)), fill=fur)
    d.ellipse(box(128, 120, 84, 52), fill=fur)
    # White cheeks meeting at the muzzle.
    d.polygon(pts((30, 128), (88, 146), (128, 214), (72, 176)), fill=CREAM)
    d.polygon(pts((226, 128), (168, 146), (128, 214), (184, 176)), fill=CREAM)
    d.polygon(pts((88, 146), (128, 150), (168, 146), (128, 214)), fill=CREAM)
    # Eyes, nose, smile.
    eye(d, 94, 126, 9.5)
    eye(d, 162, 126, 9.5)
    d.ellipse(box(128, 196, 11, 8), fill=dark)
    d.ellipse(box(124, 193, 3.5, 2.5), fill=(255, 255, 255, 200))
    line(d, [(128, 203), (128, 210)], 3, dark)
    cheeks(img, 82, 174, 154, 9, 5)
    return img


def robot():
    bg = PURPLE
    img, d = canvas(bg)
    ground(img, bg, 128, 238, 70, 8)
    body = CREAM
    steel = (186, 178, 170)
    screen = (38, 33, 48)
    # Antenna.
    line(d, [(128, 64), (128, 36)], 6, steel)
    d.ellipse(box(128, 32, 12, 12), fill=ACCENT)
    d.ellipse(box(124, 28, 4, 4), fill=(255, 200, 185))
    # Ears.
    d.rounded_rectangle((u(30), u(108), u(52), u(170)), radius=u(9), fill=steel)
    d.rounded_rectangle((u(204), u(108), u(226), u(170)), radius=u(9), fill=steel)
    # Neck and shoulders.
    d.rectangle((u(108), u(196), u(148), u(214)), fill=steel)
    d.rounded_rectangle((u(62), u(206), u(194), u(270)), radius=u(26), fill=body)
    d.ellipse(box(128, 232, 9, 9), fill=ACCENT)
    # Head and screen.
    d.rounded_rectangle((u(44), u(62), u(212), u(204)), radius=u(36), fill=body)
    d.rounded_rectangle((u(64), u(84), u(192), u(182)), radius=u(24), fill=screen)
    # Glowing eyes and smile.
    for x in (100, 156):
        d.ellipse(box(x, 124, 15, 15), fill=shade(YELLOW, -0.35))
        d.ellipse(box(x, 122, 12, 12), fill=YELLOW)
        d.ellipse(box(x + 4, 117, 4, 4), fill=(255, 250, 225))
    arc(d, 128, 146, 20, 16, 25, 155, 5, TEAL)
    # Bolts.
    for x, y in ((56, 74), (200, 74), (56, 192), (200, 192)):
        d.ellipse(box(x, y, 4, 4), fill=steel)
    return img


def panda():
    bg = ROSE
    img, d = canvas(bg)
    black = (34, 31, 36)
    white = (252, 250, 247)
    # Ears.
    d.ellipse(box(62, 70, 30, 30), fill=black)
    d.ellipse(box(194, 70, 30, 30), fill=black)
    # Body.
    d.ellipse(box(128, 272, 94, 62), fill=black)
    d.ellipse(box(128, 286, 50, 48), fill=white)
    # Head.
    d.ellipse(box(128, 140, 96, 84), fill=white)
    # Eye patches, tilted.
    for side in (-1, 1):
        patch = Image.new("RGBA", (u(56), u(70)), (0, 0, 0, 0))
        ImageDraw.Draw(patch).ellipse((0, 0, u(56) - 1, u(70) - 1), fill=black)
        patch = patch.rotate(side * 32, resample=Image.BICUBIC, expand=True)
        cx, cy = 128 + side * 38, 132
        img.alpha_composite(patch, (round(u(cx) - patch.width / 2), round(u(cy) - patch.height / 2)))
    d = ImageDraw.Draw(img)
    for side in (-1, 1):
        cx = 128 + side * 36
        d.ellipse(box(cx, 128, 10, 11), fill=white)
        d.ellipse(box(cx + side * 1, 130, 6, 7), fill=black)
        d.ellipse(box(cx + side * 1 + 2, 127, 2.2, 2.2), fill=white)
    # Nose and smile.
    d.ellipse(box(128, 164, 13, 9), fill=black)
    line(d, [(128, 170), (128, 178)], 3.4, black)
    arc(d, 119, 176, 9, 8, 10, 140, 3.4, black)
    arc(d, 137, 176, 9, 8, 40, 170, 3.4, black)
    cheeks(img, 74, 182, 170, 11, 6)
    return img


AVATARS = {
    "popcorn": popcorn,
    "clap": clap,
    "chat": cat,
    "renard": fox,
    "robot": robot,
    "panda": panda,
}


def main():
    out_dir = os.path.join("assets", "avatars")
    os.makedirs(out_dir, exist_ok=True)
    for name, draw in AVATARS.items():
        img = draw().convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
        path = os.path.join(out_dir, f"{name}.png")
        img.save(path, optimize=True)
        print(path, os.path.getsize(path), "octets")


if __name__ == "__main__":
    main()
