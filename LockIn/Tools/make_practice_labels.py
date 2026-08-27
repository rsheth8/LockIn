#!/usr/bin/env python3
"""Renders practice data for the barcode and nutrition-label scanners.

Both scanners need something real to point at, and neither can be exercised
from a unit test alone — the label reader's hard part is Vision's row grouping
on a two-column panel, and the barcode reader needs an actual scannable
symbol. Hand-written test strings prove the parser; these prove the pipeline.

Produces, into --out (default: ./practice):

  label_*.png    Nutrition Facts panels in the three layouts that matter —
                 the current FDA format, a high-protein bar, and the older
                 1994 format that puts "Calories from Fat" on the same visual
                 row as the calorie count.
  barcodes.png   A sheet of real EAN-13 symbols for products that are actually
                 in Open Food Facts, big enough to scan off a monitor.

Usage:
    python3 LockIn/Tools/make_practice_labels.py --out /tmp/practice

Then, for the simulator (the label reader's "Choose an existing photo" path):
    xcrun simctl addmedia booted /tmp/practice/label_*.png
"""

import argparse
import os
from PIL import Image, ImageDraw, ImageFont

FONT_DIR = "/System/Library/Fonts/Supplemental"
REGULAR = os.path.join(FONT_DIR, "Helvetica.ttc")
BOLD = os.path.join(FONT_DIR, "Helvetica.ttc")

# Panels are rendered at print-ish resolution: the point of this data is to
# behave like a photograph of a box, and Vision's accuracy falls off a cliff on
# small text.
WIDTH = 900
MARGIN = 40


def font(size, bold=False):
    try:
        return ImageFont.truetype(BOLD if bold else REGULAR, size, index=1 if bold else 0)
    except OSError:
        return ImageFont.load_default(size)


class Panel:
    """A Nutrition Facts panel drawn top-down.

    Rows are drawn as a label on the left and a value on the right, which is
    the whole reason this generator exists: that split is what the reader has
    to put back together from separate Vision observations.
    """

    def __init__(self, width=WIDTH):
        self.width = width
        self.image = Image.new("RGB", (width, 2400), "white")
        self.draw = ImageDraw.Draw(self.image)
        self.y = MARGIN

    def text(self, value, size, bold=False, indent=0, gap=6):
        self.draw.text((MARGIN + indent, self.y), value, font=font(size, bold), fill="black")
        self.y += size + gap

    def row(self, label, value, size=30, bold=False, indent=0, right=None, gap=8):
        f = font(size, bold)
        self.draw.text((MARGIN + indent, self.y), label, font=f, fill="black")
        if right is None:
            # Two-column row: "Serving size" hard left, "2/3 cup (55g)" hard
            # right, nothing between them.
            if value:
                w = self.draw.textlength(value, font=f)
                self.draw.text((self.width - MARGIN - w, self.y), value, font=f, fill="black")
        else:
            # Nutrient row: the gram figure sits inline after its label and the
            # % Daily Value takes the right column — a three-piece line that
            # Vision hands back as separate observations.
            if value:
                wl = self.draw.textlength(label, font=f)
                self.draw.text((MARGIN + indent + wl + 12, self.y), value, font=f, fill="black")
            if right:
                fr = font(size, False)
                w = self.draw.textlength(right, font=fr)
                self.draw.text((self.width - MARGIN - w, self.y), right, font=fr, fill="black")
        self.y += size + gap

    def rule(self, thickness=3, pad=10):
        self.y += pad
        self.draw.rectangle(
            [MARGIN, self.y, self.width - MARGIN, self.y + thickness], fill="black"
        )
        self.y += thickness + pad

    def save(self, path):
        cropped = self.image.crop((0, 0, self.width, self.y + MARGIN))
        cropped.save(path)
        print(f"  {os.path.basename(path)}  {cropped.width}x{cropped.height}")


def modern_panel(path, title, servings, serving_size, calories, rows):
    """The current (2016) FDA format — oversized calorie figure, no
    'calories from fat' line."""
    p = Panel()
    p.text("Nutrition Facts", 64, bold=True, gap=4)
    p.draw.rectangle([MARGIN, p.y, WIDTH - MARGIN, p.y + 2], fill="black")
    p.y += 14
    p.text(servings, 28)
    p.row("Serving size", serving_size, size=32, bold=True)
    p.rule(thickness=14)
    p.text("Amount per serving", 24, bold=True, gap=2)
    p.row("Calories", str(calories), size=58, bold=True)
    p.rule(thickness=6)
    f = font(24, bold=True)
    w = p.draw.textlength("% Daily Value*", font=f)
    p.draw.text((WIDTH - MARGIN - w, p.y), "% Daily Value*", font=f, fill="black")
    p.y += 32
    for label, value, dv, indent, bold in rows:
        p.row(label, value, size=28, bold=bold, indent=indent, right=dv)
        p.draw.rectangle([MARGIN, p.y - 4, WIDTH - MARGIN, p.y - 3], fill="#999999")
    p.rule(thickness=14)
    p.text("* The % Daily Value tells you how much a nutrient in a", 18)
    p.text("serving of food contributes to a daily diet.", 18)
    p.save(path)


def legacy_panel(path, serving_size, servings, calories, from_fat, rows):
    """The pre-2016 format. Its calorie line is two columns wide — 'Calories
    140' on the left, 'Calories from Fat 30' on the right — so it lands in the
    reader as a single row containing both."""
    p = Panel()
    p.text("Nutrition Facts", 56, bold=True, gap=4)
    p.draw.rectangle([MARGIN, p.y, WIDTH - MARGIN, p.y + 2], fill="black")
    p.y += 12
    p.text(f"Serving Size {serving_size}", 26)
    p.text(f"Servings Per Container {servings}", 26)
    p.rule(thickness=10)
    p.text("Amount Per Serving", 24, bold=True, gap=4)
    p.row("Calories " + str(calories), None, size=32, bold=True, gap=2)
    f = font(26, bold=False)
    label = f"Calories from Fat {from_fat}"
    w = p.draw.textlength(label, font=f)
    p.y -= 34
    p.draw.text((WIDTH - MARGIN - w, p.y), label, font=f, fill="black")
    p.y += 44
    p.rule(thickness=4)
    f = font(22, bold=True)
    w = p.draw.textlength("% Daily Value*", font=f)
    p.draw.text((WIDTH - MARGIN - w, p.y), "% Daily Value*", font=f, fill="black")
    p.y += 30
    for label, value, dv, indent, bold in rows:
        p.row(label, value, size=26, bold=bold, indent=indent, right=dv)
        p.draw.rectangle([MARGIN, p.y - 4, WIDTH - MARGIN, p.y - 3], fill="#999999")
    p.rule(thickness=10)
    p.text("* Percent Daily Values are based on a 2,000 calorie diet.", 18)
    p.save(path)


# --- EAN-13 -----------------------------------------------------------------
#
# Written out rather than pulled from a package so the practice sheet carries
# genuine symbols: a scanner reading one of these returns the same digits Open
# Food Facts is keyed on, which is the only way to prove the path end to end.

L = ["0001101", "0011001", "0010011", "0111101", "0100011",
     "0110001", "0101111", "0111011", "0110111", "0001011"]
G = ["0100111", "0110011", "0011011", "0100001", "0011101",
     "0111001", "0000101", "0010001", "0001001", "0010111"]
R = ["".join("1" if c == "0" else "0" for c in code) for code in L]
PARITY = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG",
          "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]


def ean13_bits(digits):
    assert len(digits) == 13 and digits.isdigit(), digits
    d = [int(c) for c in digits]
    check = (10 - sum(d[i] * (3 if i % 2 else 1) for i in range(12)) % 10) % 10
    assert check == d[12], f"{digits}: check digit should be {check}"
    bits = "101"
    pattern = PARITY[d[0]]
    for i, digit in enumerate(d[1:7]):
        bits += (L if pattern[i] == "L" else G)[digit]
    bits += "01010"
    for digit in d[7:]:
        bits += R[digit]
    return bits + "101"


def draw_barcode(draw, x, y, digits, module=4, height=180):
    bits = ean13_bits(digits)
    quiet = module * 9
    total = len(bits) * module
    draw.rectangle([x, y, x + total + quiet * 2, y + height + 46], fill="white")
    for i, bit in enumerate(bits):
        if bit == "1":
            # Guard bars run longer, as on a real symbol.
            guard = i < 3 or i >= len(bits) - 3 or 45 <= i <= 49
            draw.rectangle(
                [x + quiet + i * module, y,
                 x + quiet + (i + 1) * module - 1, y + height + (14 if guard else 0)],
                fill="black",
            )
    f = font(26)
    draw.text((x + quiet, y + height + 18), " ".join(digits), font=f, fill="black")
    return total + quiet * 2


def barcode_sheet(path, products):
    height, gap = 260, 40
    image = Image.new("RGB", (760, MARGIN * 2 + 70 + len(products) * (height + gap)), "white")
    draw = ImageDraw.Draw(image)
    draw.text((MARGIN, MARGIN), "LockIn — practice barcodes", font=font(34, bold=True), fill="black")
    draw.text((MARGIN, MARGIN + 42), "Point the scanner at one of these.", font=font(22), fill="#555555")
    y = MARGIN + 90
    for digits, name in products:
        draw.text((MARGIN, y), name, font=font(24, bold=True), fill="black")
        draw_barcode(draw, MARGIN, y + 34, digits)
        y += height + gap
    image.save(path)
    print(f"  {os.path.basename(path)}  {image.width}x{image.height}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="practice")
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    out = lambda name: os.path.join(args.out, name)

    print("Rendering practice data:")

    modern_panel(
        out("label_granola.png"),
        "Granola", "About 8 servings per container", "2/3 cup (55g)", 230,
        [("Total Fat", "8g", "10%", 0, True),
         ("Saturated Fat", "1g", "5%", 26, False),
         ("Trans Fat", "0g", "", 26, False),
         ("Cholesterol", "0mg", "0%", 0, True),
         ("Sodium", "160mg", "7%", 0, True),
         ("Total Carbohydrate", "37g", "13%", 0, True),
         ("Dietary Fiber", "4g", "14%", 26, False),
         ("Total Sugars", "12g", "", 26, False),
         ("Includes 10g Added Sugars", "", "20%", 52, False),
         ("Protein", "3g", "", 0, True)],
    )

    modern_panel(
        out("label_protein_bar.png"),
        "Protein bar", "1 servings per container", "1 bar (60g)", 190,
        [("Total Fat", "8g", "10%", 0, True),
         ("Saturated Fat", "3g", "15%", 26, False),
         ("Trans Fat", "0g", "", 26, False),
         ("Cholesterol", "5mg", "2%", 0, True),
         ("Sodium", "220mg", "10%", 0, True),
         ("Total Carbohydrate", "22g", "8%", 0, True),
         ("Dietary Fiber", "14g", "50%", 26, False),
         ("Total Sugars", "1g", "", 26, False),
         ("Protein", "21g", "42%", 0, True)],
    )

    legacy_panel(
        out("label_tortillas.png"),
        "1 tortilla (49g)", 8, 140, 30,
        [("Total Fat", "3.5g", "5%", 0, True),
         ("Saturated Fat", "1g", "5%", 26, False),
         ("Trans Fat", "0g", "", 26, False),
         ("Cholesterol", "0mg", "0%", 0, True),
         ("Sodium", "350mg", "15%", 0, True),
         ("Total Carbohydrate", "24g", "8%", 0, True),
         ("Dietary Fiber", "1g", "4%", 26, False),
         ("Sugars", "1g", "", 26, False),
         ("Protein", "4g", "", 0, True)],
    )

    barcode_sheet(out("barcodes.png"), [
        ("0096619160754", "Kirkland Signature Chewy Protein Bar"),
        ("0888849000012", "Quest Chocolate Chip Cookie Dough Bar"),
        ("0894700010045", "Chobani Greek Yogurt, Strawberry"),
        ("0030000010204", "Quaker Old Fashioned Rolled Oats"),
        # A valid EAN-13 that Open Food Facts genuinely doesn't have, so the
        # "unknown code, scan the label instead" path can be exercised too.
        ("0765432109874", "Not in the database (tests the fallback)"),
    ])


if __name__ == "__main__":
    main()
