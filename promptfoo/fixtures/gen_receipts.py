#!/usr/bin/env python3
"""
Generate synthetic receipt PNGs for promptfoo eval of receipt-ingest.
Covers: multi-language, multi-currency, tip, multi-item, card last4,
income/refund, near-illegible, ambiguous total.

Output: promptfoo/fixtures/receipts/*.png
"""

import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT_DIR = os.path.join(os.path.dirname(__file__), "receipts")
W = 420  # receipt width

# ── Font paths (macOS system fonts) ──
FONT_LATIN     = "/System/Library/Fonts/Helvetica.ttc"
FONT_ARABIC    = "/System/Library/Fonts/SFArabic.ttf"
FONT_GEORGIAN  = "/System/Library/Fonts/SFGeorgian.ttf"

# ── Helpers ──

def load_font(path: str, size: int, index: int = 0) -> ImageFont.FreeTypeFont:
    """Load a TrueType/OpenType font, falling back to default."""
    try:
        return ImageFont.truetype(path, size, index=index)
    except Exception:
        return ImageFont.load_default()

def text_size(draw: ImageDraw.Draw, text: str, font: ImageFont.FreeTypeFont) -> tuple[int, int]:
    bbox = draw.textbbox((0, 0), text, font=font)
    return (bbox[2] - bbox[0], bbox[3] - bbox[1])

def draw_receipt(
    *,
    filename: str,
    merchant: str,
    date: str,
    lines: list[tuple[str, str]],   # (item, price) — price string includes currency symbol
    total: str,                      # e.g. "$12.50"
    footer: str | None = None,       # e.g. "Card ending: 9876"
    tip: str | None = None,
    refund: bool = False,
    lang: str = "en",               # en, ka, ru, ar, es
    degrade: str | None = None,     # "low_contrast", "blur", "smudge_total"
    time_str: str | None = "14:32",
) -> None:
    """Draw a synthetic receipt PNG."""

    # Font selection
    if lang == "ar":
        font_title = load_font(FONT_ARABIC, 22)
        font_body  = load_font(FONT_ARABIC, 15)
        font_small = load_font(FONT_ARABIC, 12)
        is_rtl = True
    elif lang == "ka":
        font_title = load_font(FONT_GEORGIAN, 22)
        font_body  = load_font(FONT_GEORGIAN, 15)
        font_small = load_font(FONT_GEORGIAN, 12)
        is_rtl = False
    else:
        # Latin / Cyrillic — Helvetica handles both
        font_title = load_font(FONT_LATIN, 22)
        font_body  = load_font(FONT_LATIN, 15)
        font_small = load_font(FONT_LATIN, 12)
        is_rtl = False

    # Calculate height: header + lines + optional sections + padding
    h = 50  # top margin
    h += 30  # merchant
    h += 22  # date + time
    h += 10  # spacer
    h += 18 * len(lines)  # line items
    if tip:
        h += 20
    h += 22  # total line
    h += 12  # spacer before footer
    if footer:
        h += 18
    h += 30  # bottom margin

    img = Image.new("RGB", (W, h), "white")
    draw = ImageDraw.Draw(img)

    y = 50
    cx = W // 2  # center x

    if is_rtl:
        # For RTL, align text to the right side
        def draw_centered(text, font, y_pos, fill="black"):
            tw, _ = text_size(draw, text, font)
            draw.text((W - 30 - tw, y_pos), text, font=font, fill=fill)
        def draw_left(text, font, y_pos, fill="black"):  # "left" in RTL = right-aligned
            tw, _ = text_size(draw, text, font)
            draw.text((W - 30 - tw, y_pos), text, font=font, fill=fill)
        def draw_right(text, font, y_pos, fill="black"):  # "right" in RTL = left-aligned
            draw.text((30, y_pos), text, font=font, fill=fill)
    else:
        def draw_centered(text, font, y_pos, fill="black"):
            tw, _ = text_size(draw, text, font)
            draw.text((cx - tw // 2, y_pos), text, font=font, fill=fill)
        def draw_left(text, font, y_pos, fill="black"):
            draw.text((30, y_pos), text, font=font, fill=fill)
        def draw_right(text, font, y_pos, fill="black"):
            tw, _ = text_size(draw, text, font)
            draw.text((W - 30 - tw, y_pos), text, font=font, fill=fill)

    # ── Merchant name ──
    draw_centered(merchant, font_title, y)
    y += 28
    draw_centered("-" * 32, font_small, y, fill="gray")
    y += 4

    # ── Date & time ──
    draw_centered(f"{date}  {time_str}", font_small, y, fill="gray")
    y += 24

    # ── Line items ──
    for item, price in lines:
        draw_left(item, font_body, y)
        draw_right(price, font_body, y)
        y += 18

    # ── Separator ──
    draw_centered("-" * 36, font_small, y, fill="gray")
    y += 2

    # ── Tip (optional) ──
    if tip:
        draw_left(tip, font_body, y)
        y += 20

    # ── Total ──
    total_text = f"TOTAL: {total}"
    if refund:
        total_text = f"REFUND: {total}"
    tw, _ = text_size(draw, total_text, font_title)
    draw.text((cx - tw // 2, y), total_text, font=font_title, fill="black")
    y += 26

    # ── Footer ──
    if footer:
        draw_centered("-" * 32, font_small, y, fill="gray")
        y += 2
        draw_centered(footer, font_small, y, fill="gray")
        y += 18

    # ── Thank you ──
    draw_centered("Thank you!", font_small, y, fill="gray")

    # ── Degradation effects ──
    if degrade == "low_contrast":
        # Extreme: near-white, heavy blur, random noise — should be very hard
        img = img.convert("L")
        img = img.point(lambda p: int(p * 0.08 + 225))
        img = img.filter(ImageFilter.GaussianBlur(radius=4.0))
        # Add salt-and-pepper noise
        import random as _random
        pixels = img.load()
        for _i in range(img.size[0] * img.size[1] // 3):
            rx = _random.randint(0, img.size[0] - 1)
            ry = _random.randint(0, img.size[1] - 1)
            pixels[rx, ry] = _random.randint(0, 255)
        img = img.convert("RGB")

    if degrade == "blur":
        img = img.filter(ImageFilter.GaussianBlur(radius=5.0))
        # Add heavy noise on top
        import random as _random2
        pixels = img.load()
        for _i in range(img.size[0] * img.size[1] // 2):
            rx = _random2.randint(0, img.size[0] - 1)
            ry = _random2.randint(0, img.size[1] - 1)
            r, g, b = pixels[rx, ry]
            shift = _random2.randint(-80, 80)
            pixels[rx, ry] = (max(0, min(255, r + shift)), max(0, min(255, g + shift)), max(0, min(255, b + shift)))
        img = img.filter(ImageFilter.GaussianBlur(radius=1.5))

    if degrade == "smudge_total":
        # Solid black rectangle completely obliterating the total line
        overlay = Image.new("RGBA", (W, h), (255, 255, 255, 0))
        ov_draw = ImageDraw.Draw(overlay)
        # Opaque black bar covering TOTAL line with rough edges
        ov_draw.rectangle([cx - 100, y - 30, cx + 100, y + 12], fill=(10, 10, 10, 250))
        # Extra blotches to make it clearly unreadable
        ov_draw.rectangle([cx - 70, y - 26, cx + 85, y + 8], fill=(5, 5, 5, 255))
        img = img.convert("RGBA")
        img = Image.alpha_composite(img, overlay)
        img = img.convert("RGB")

    # ── Noise for some realism ──
    # Add very subtle noise to all receipts for authentic thermal-print look
    import random
    pixels = img.load()
    for i in range(W * h // 40):  # ~2.5% pixels
        rx = random.randint(0, W - 1)
        ry = random.randint(0, h - 1)
        r, g, b = pixels[rx, ry]
        shift = random.randint(-12, 12)
        pixels[rx, ry] = (
            max(0, min(255, r + shift)),
            max(0, min(255, g + shift)),
            max(0, min(255, b + shift)),
        )

    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = os.path.join(OUT_DIR, filename)
    img.save(out_path, "PNG")
    print(f"  ✓ {filename}  ({W}x{h})")


# ═══════════════════════════════════════════════════════════════
# Fixture generation
# ═══════════════════════════════════════════════════════════════

def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    # 1 — English / USD café
    draw_receipt(
        filename="en_usd_cafe.png",
        merchant="Blue Bottle Coffee",
        date="2026-06-15",
        lines=[
            ("Latte (12oz)", "$4.50"),
            ("Croissant", "$3.75"),
            ("Cappuccino", "$4.25"),
        ],
        total="$12.50",
        footer="Cash",
        lang="en",
    )

    # 2 — English / EUR grocery
    draw_receipt(
        filename="en_eur_grocery.png",
        merchant="ALDI Berlin",
        date="2026-06-14",
        lines=[
            ("Bread (rye loaf)", "€2.49"),
            ("Butter 250g", "€2.99"),
            ("Eggs (6-pack)", "€3.59"),
            ("Tomatoes 500g", "€1.89"),
            ("Pasta 1kg", "€1.29"),
            ("Cheese (Gouda)", "€4.50"),
        ],
        total="€16.75",
        footer="EC-Karte",
        lang="en",
    )

    # 3 — Georgian / GEL (ქართული)
    draw_receipt(
        filename="ka_gel_market.png",
        merchant="ნიკორა სუპერმარკეტი",
        date="2026-06-16",
        lines=[
            ("პური", "₾1.80"),
            ("ყველი სულგუნი", "₾8.50"),
            ("ხაჭაპური", "₾6.00"),
            ("წყალი ბორჯომი", "₾2.40"),
            ("ღვინო", "₾15.00"),
        ],
        total="₾33.70",
        footer="ბარათი ****4321",
        lang="ka",
    )

    # 4 — Russian / RUB (кириллица)
    draw_receipt(
        filename="ru_rub_pharmacy.png",
        merchant="Аптека Горздрав",
        date="2026-06-17",
        lines=[
            ("Парацетамол 500мг", "₽245.00"),
            ("Ибупрофен гель", "₽389.00"),
            ("Витамин D3", "₽156.00"),
            ("Маска медицинская", "₽100.00"),
        ],
        total="₽890.00",
        footer="Карта ****6789",
        lang="ru",
    )

    # 5 — Arabic / AED (right-to-left)
    draw_receipt(
        filename="ar_aed_restaurant.png",
        merchant="مطعم البيت اللبناني",
        date="2026-06-18",
        lines=[
            ("حمص", "35.00 د.إ"),
            ("تبولة", "28.00 د.إ"),
            ("شاورما دجاج", "42.00 د.إ"),
            ("عصير ليمون", "18.00 د.إ"),
            ("كنافة", "27.00 د.إ"),
        ],
        total="150.00 د.إ",
        footer="بطاقة ائتمان",
        lang="ar",
    )

    # 6 — English / USD with tip line
    draw_receipt(
        filename="en_usd_tip.png",
        merchant="The River Grill",
        date="2026-06-19",
        lines=[
            ("Grilled Salmon", "$28.00"),
            ("Caesar Salad", "$12.00"),
            ("Sparkling Water", "$5.00"),
        ],
        total="$54.00",
        tip="Tip:           $9.00",
        footer="Visa ending 3456",
        lang="en",
    )

    # 7 — English / GBP multi-item (7 lines)
    draw_receipt(
        filename="en_gbp_multi.png",
        merchant="Tesco Express",
        date="2026-06-20",
        lines=[
            ("Milk (whole, 2L)", "£2.10"),
            ("Bananas (5)", "£1.25"),
            ("Sourdough Bread", "£3.40"),
            ("Free-range Eggs (6)", "£3.20"),
            ("Avocado (2)", "£2.50"),
            ("Greek Yogurt 500g", "£3.00"),
            ("Dark Chocolate 70%", "£2.50"),
        ],
        total="£17.95",
        footer="Clubcard accepted",
        lang="en",
    )

    # 8 — English / USD with card last-4 printed
    draw_receipt(
        filename="en_usd_card.png",
        merchant="Whole Foods Market",
        date="2026-06-21",
        lines=[
            ("Organic Kale", "$3.99"),
            ("Quinoa 1lb", "$4.49"),
            ("Almond Milk", "$3.79"),
            ("Granola", "$5.29"),
            ("Honey (local)", "$8.99"),
        ],
        total="$26.55",
        footer="Card ending: 9876  |  Approved",
        lang="en",
    )

    # 9 — English / EUR refund (income)
    draw_receipt(
        filename="en_eur_refund.png",
        merchant="Zara Returns",
        date="2026-06-13",
        lines=[
            ("Linen Dress (return)", "-€39.99"),
            ("Cotton Shirt (return)", "-€25.00"),
        ],
        total="-€64.99",
        refund=True,
        footer="Refund to original card ****1234",
        lang="en",
    )

    # 10 — English / USD near-illegible (low confidence expected)
    draw_receipt(
        filename="en_usd_illegible.png",
        merchant="Faded Print Diner",
        date="2026-06-10",
        lines=[
            ("Burger", "$9.00"),
            ("Fries", "$4.00"),
            ("Soda", "$2.50"),
        ],
        total="$15.50",
        footer="Card ****1111",
        lang="en",
        degrade="low_contrast",
    )

    # 11 — English / USD ambiguous total (expect needs_clarification)
    draw_receipt(
        filename="en_usd_ambiguous.png",
        merchant="Quick Stop Mart",
        date="2026-06-22",
        lines=[
            ("Chips", "$2.99"),
            ("Soda (20oz)", "$1.99"),
            ("Candy Bar", "$1.50"),
        ],
        total="$6.48",
        footer="Cash",
        lang="en",
        degrade="smudge_total",
    )

    # 12 — Spanish / MXN restaurant
    draw_receipt(
        filename="es_mxn_restaurant.png",
        merchant="Taquería El Pastor",
        date="2026-06-19",
        lines=[
            ("Tacos al Pastor (3)", "$85.00"),
            ("Quesadilla", "$65.00"),
            ("Agua de Horchata", "$35.00"),
            ("Guacamole", "$45.00"),
        ],
        total="$230.00",
        footer="Efectivo",
        lang="es",
    )

    # 13 — English / USD with line items having quantities (bonus)
    draw_receipt(
        filename="en_usd_quantity.png",
        merchant="Office Depot",
        date="2026-06-21",
        lines=[
            ("Printer Paper (x2)", "$19.98"),
            ("Ballpoint Pens (x12)", "$8.40"),
            ("Sticky Notes (x3)", "$5.97"),
        ],
        total="$34.35",
        footer="Card ****5555",
        lang="en",
    )

    print(f"\nGenerated {13} receipt fixtures → {OUT_DIR}/")


if __name__ == "__main__":
    main()
