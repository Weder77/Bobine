"""Draws the Bobine icon (a spool of vermilion thread on a dark rounded
square, from assets/icon/bobine.svg) in every size the platforms need.
Run from the repository root: python3 tool/make_icon.py"""
from PIL import Image, ImageDraw

# Colours and geometry of assets/icon/bobine.svg (viewBox 0 0 32 32).
BG = (13, 12, 11)  # #0D0C0B
ACCENT = (255, 90, 54)  # #FF5A36
STRIPE = (184, 58, 29)  # #B83A1D
CREAM = (243, 238, 232)  # #F3EEE8


def icon(size: int) -> Image.Image:
    ss = 4  # supersampling for smooth edges
    big = size * ss
    k = big / 32  # SVG unit -> pixels

    def p(x: float, y: float) -> tuple[float, float]:
        return (x * k, y * k)

    out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    # Dark rounded square.
    d.rounded_rectangle((0, 0, big - 1, big - 1), radius=7 * k, fill=BG)
    # Core of the spool and the wound thread.
    d.rectangle((*p(6.5, 9.5), *p(19.5, 22.5)), fill=ACCENT)
    for y in (13, 16.4, 19.8):
        d.line((*p(6.5, y), *p(19.5, y + 1.2)), fill=STRIPE, width=max(1, round(1.1 * k)))
    # Flanges.
    d.rounded_rectangle((*p(4, 5), *p(22, 9.5)), radius=1.5 * k, fill=CREAM)
    d.rounded_rectangle((*p(4, 22.5), *p(22, 27)), radius=1.5 * k, fill=CREAM)
    # Loose end of the thread: cubic Bézier, round caps.
    p0, p1, p2, p3 = (19.5, 20.2), (23.1, 20.6), (25.1, 22.5), (26.5, 26.5)
    pts = []
    for i in range(65):
        t = i / 64
        u = 1 - t
        x = u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]
        pts.append(p(x, y))
    w = 2.2 * k
    d.line(pts, fill=ACCENT, width=round(w), joint="curve")
    for x, y in (pts[0], pts[-1]):
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=ACCENT)
    return out.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    base = icon(1024)
    for path in ("assets/icon/bobine.png", "docs/icon.png"):
        base.resize((256, 256), Image.LANCZOS).save(path)
    for n in (16, 32, 64, 128, 256, 512, 1024):
        icon(n).save(f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{n}.png")
    # Small sizes are drawn on their own (not shrunk) so the thread stays sharp.
    sizes = [16, 24, 32, 48, 64, 128, 256]
    images = [icon(n) for n in sizes]
    images[-1].save(
        "windows/runner/resources/app_icon.ico",
        sizes=[(n, n) for n in sizes],
        append_images=images[:-1],
    )
