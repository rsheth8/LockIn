"""Full-vocabulary evaluation: real photos vs all 704 vocabulary entries."""

import glob
import json
import os

import numpy as np
import coremltools as ct
from PIL import Image

# filename stem -> labels we'd accept as a correct identification
ACCEPT = {
    "Palak_paneer": {"palak paneer", "matar paneer", "kadai paneer", "shahi paneer", "paneer butter masala", "saag"},
    "Masala_dosa": {"masala dosa", "plain dosa", "rava dosa", "onion uttapam"},
    "Biryani": {"chicken biryani", "vegetable biryani", "mutton biryani", "hyderabadi biryani", "biryani rice", "biryani with raita", "pulao", "vegetable pulao"},
    "Pad_thai": {"pad thai", "pad see ew", "drunken noodles", "yakisoba", "chow mein", "lo mein"},
    "Pho": {"pho noodle soup", "bun bo hue", "beef noodle soup", "ramen noodle soup", "udon noodle soup", "taiwanese beef noodle"},
    "Jollof_rice": {"jollof rice", "fried rice", "thai fried rice", "pulao", "paella", "seafood paella", "biryani rice"},
    "Injera": {"injera with wot", "doro wat", "shiro", "misir wot", "tibs"},
    "Shakshouka": {"shakshuka", "menemen", "huevos rancheros", "tomato soup"},
    "Taco": {"tacos", "carne asada tacos", "al pastor tacos", "fish tacos"},
    "Sushi": {"sushi rolls", "nigiri sushi", "sashimi", "california roll", "spicy tuna roll", "chirashi bowl", "kimbap"},
    "Hamburger": {"cheeseburger", "hamburger", "bacon cheeseburger", "smash burger"},
    "Caesar_salad": {"caesar salad", "cobb salad", "garden salad", "side salad", "salad bowl", "greek salad"},
    "Bibimbap": {"bibimbap", "japchae", "poke bowl", "grain bowl", "buddha bowl"},
    "Feijoada": {"feijoada", "black beans", "pozole", "menudo", "ropa vieja", "rajma", "dal makhani"},
    "Pizza": {"margherita pizza", "neapolitan pizza", "pepperoni pizza", "calzone"},
    "Ramen": {"ramen noodle soup", "tonkotsu ramen", "shoyu ramen", "miso ramen", "udon noodle soup", "pho noodle soup"},
    "Falafel": {"falafel", "hummus", "sambusak", "pakora", "arancini"},
    "Tteokbokki": {"tteokbokki", "korean fried chicken", "kimchi jjigae"},
    "Chicken_tikka_masala": {"chicken tikka masala", "butter chicken", "chicken curry", "paneer butter masala", "korma", "rogan josh", "vindaloo"},
    "Ceviche": {"ceviche", "poke bowl", "shrimp", "sashimi"},
    "Pierogi": {"pierogi", "dumplings", "gyoza dumplings", "ravioli", "momo dumplings"},
    "Croissant": {"croissant", "pain au chocolat", "scones with cream"},
    "Dim_sum": {"dim sum platter", "siu mai", "har gow", "soup dumplings", "xiao long bao", "dumplings", "char siu bao"},
    "Hummus": {"hummus", "baba ganoush", "labneh", "guacamole"},
}


def main():
    model = ct.models.MLModel("models/mobileclip_s0_image.mlpackage")
    meta = json.load(open("FoodVocabulary.json"))
    names, dims, food_count = meta["names"], meta["dimensions"], meta["foodCount"]
    matrix = np.fromfile("FoodVocabulary.bin", dtype=np.float16).reshape(-1, dims).astype(np.float32)

    top1 = top5 = total = 0
    misses = []
    for path in sorted(glob.glob("testimg/*.jpg")):
        stem = os.path.basename(path).replace(".jpg", "")
        accepted = ACCEPT.get(stem)
        if not accepted:
            continue

        im = Image.open(path).convert("RGB")
        w, h = im.size
        s = min(w, h)
        im = im.crop(((w - s) // 2, (h - s) // 2, (w + s) // 2, (h + s) // 2)).resize((256, 256), Image.BICUBIC)
        emb = np.asarray(model.predict({"image": im})["final_emb_1"], np.float32).reshape(-1)
        emb /= np.linalg.norm(emb)

        sims = matrix @ emb
        order = np.argsort(-sims)[:5]
        guesses = [names[i] for i in order]

        total += 1
        hit1 = guesses[0] in accepted
        hit5 = any(g in accepted for g in guesses)
        top1 += hit1
        top5 += hit5
        if not hit5:
            misses.append(stem)

        mark = "OK  " if hit1 else ("top5" if hit5 else "MISS")
        best_nonfood = max((sims[i] for i in range(food_count, len(names))), default=0.0)
        print(f"{mark} {stem:22s} {', '.join(f'{g} ({sims[i]:.2f})' for g, i in zip(guesses, order))}"
              f"   [nonfood {best_nonfood:.2f}]")

    print(f"\ntop-1 {top1}/{total} ({top1/total:.0%})   top-5 {top5}/{total} ({top5/total:.0%})")
    if misses:
        print("misses:", misses)


if __name__ == "__main__":
    main()
