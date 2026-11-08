"""Draws the Bobine icon (amber rounded square, dark "B") in every size the
platforms need. Run from the repository root: python3 tool/make_icon.py"""
from PIL import Image, ImageDraw, ImageFont

FONT = "assets/fonts/Inter-ExtraBold.ttf"
TOP, BOTTOM = (255, 196, 102), (255, 122, 69)  # amber -> orange, top-left to bottom-right
INK = (27, 18, 4)


def icon(size: int) -> Image.Image:
    s = 4  # supersampling for smooth edges
    big = size * s
    grad = Image.new("RGBA", (big, big))
    px = grad.load()
    for y in range(big):
        for x in range(big):
            t = (x + y) / (2 * (big - 1))
            px[x, y] = tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)) + (255,)
    mask = Image.new("L", (big, big), 0)
    margin = round(big * 0.04)
    ImageDraw.Draw(mask).rounded_rectangle((margin, margin, big - margin, big - margin), radius=round(big * 0.22), fill=255)
    out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    out.paste(grad, (0, 0), mask)
    draw = ImageDraw.Draw(out)
    font = ImageFont.truetype(FONT, round(big * 0.62))
    box = draw.textbbox((0, 0), "B", font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    draw.text(((big - w) / 2 - box[0], (big - h) / 2 - box[1]), "B", font=font, fill=INK)
    return out.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    base = icon(1024)
    for path in ("assets/icon/bobine.png", "docs/icon.png"):
        base.resize((256, 256), Image.LANCZOS).save(path)
    for n in (16, 32, 64, 128, 256, 512, 1024):
        base.resize((n, n), Image.LANCZOS).save(f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{n}.png")
    base.save("windows/runner/resources/app_icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("icons written")
