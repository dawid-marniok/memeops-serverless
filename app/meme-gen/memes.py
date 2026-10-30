"""Renderowanie memów: SVG (biblioteka standardowa) albo PNG (Pillow).

„Zdjęcia” to generowane tła, żeby repo nie zależało od plików z prawami autorskimi.
"""
from xml.sax.saxutils import escape

try:
    from PIL import Image, ImageDraw, ImageFont
    HAS_PILLOW = True
except ImportError:  # wersja SVG nie potrzebuje żadnych zależności
    HAS_PILLOW = False

BASE_W, BASE_H = 600, 400

# szablon → (kolor góra, kolor dół, ozdobnik)
TEMPLATES = {
    "keynote": ("#0b2a4a", "#2f80c9", "🎤"),
    "kawa": ("#3b2416", "#a8744f", "☕"),
    "piatek": ("#7a1010", "#f28c28", "🔥"),
    "zero": ("#2b2b2b", "#8a8a8a", "💤"),
}
DARK = {"keynote": ("#05070d", "#1c2b44"), "kawa": ("#0d0805", "#3b2a1e"),
        "piatek": ("#140303", "#4a1d06"), "zero": ("#000000", "#2b2b2b")}


def palette(template, theme):
    top, bottom, emoji = TEMPLATES.get(template, TEMPLATES["keynote"])
    if theme == "dark":
        top, bottom = DARK.get(template, DARK["keynote"])
    text = "#f5f5f5" if theme != "dark" else "#7CFFB2"
    return top, bottom, emoji, text


def render(fmt, top, bottom, template, theme="light", watermark="", scale=1):
    top, bottom = top.strip()[:60].upper(), bottom.strip()[:60].upper()
    if fmt == "png":
        return "image/png", render_png(top, bottom, template, theme, watermark, scale)
    return "image/svg+xml", render_svg(top, bottom, template, theme, watermark, scale).encode()


def render_svg(top, bottom, template, theme, watermark, scale=1):
    c1, c2, emoji, fg = palette(template, theme)
    w, h = BASE_W * scale, BASE_H * scale
    fs = 40 * scale
    wm = (f'<text x="{w - 12 * scale}" y="{h - 12 * scale}" text-anchor="end" font-size="{14 * scale}" '
          f'fill="{fg}" opacity="0.7">{escape(watermark)}</text>') if watermark else ""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">
<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/></linearGradient></defs>
<rect width="{w}" height="{h}" fill="url(#g)"/>
<text x="{w / 2}" y="{h / 2 + 30 * scale}" text-anchor="middle" font-size="{120 * scale}" opacity="0.35">{emoji}</text>
<g font-family="Impact, 'Arial Black', sans-serif" font-size="{fs}" fill="{fg}" stroke="#000" stroke-width="{2 * scale}"
 text-anchor="middle" font-weight="bold">
<text x="{w / 2}" y="{60 * scale}">{escape(top)}</text>
<text x="{w / 2}" y="{h - 40 * scale}">{escape(bottom)}</text>
</g>{wm}
</svg>"""


def _hex(c):
    return tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))


def render_png(top, bottom, template, theme, watermark, scale=1):
    import io
    c1, c2, _, fg = palette(template, theme)
    w, h = BASE_W * scale, BASE_H * scale
    img = Image.new("RGB", (w, h))
    draw = ImageDraw.Draw(img)
    a, b = _hex(c1), _hex(c2)
    for y in range(h):  # gradient liniami — celowo „kosztuje” trochę CPU, jak prawdziwa obróbka zdjęcia
        t = y / max(h - 1, 1)
        draw.line([(0, y), (w, y)], fill=tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)))
    font = ImageFont.load_default(size=40 * scale)
    for txt, y in ((top, 30 * scale), (bottom, h - 80 * scale)):
        if txt:
            draw.text((w / 2, y), txt, font=font, fill=_hex(fg), anchor="mt",
                      stroke_width=2 * scale, stroke_fill=(0, 0, 0))
    if watermark:
        draw.text((w - 12 * scale, h - 12 * scale), watermark, font=ImageFont.load_default(size=14 * scale),
                  fill=_hex(fg), anchor="rb")
    out = io.BytesIO()
    img.save(out, "PNG")
    return out.getvalue()
