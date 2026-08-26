"""Stress evaluation across ~100 dishes from every major cuisine."""

import json
import os
import sys

import numpy as np
import coremltools as ct
from PIL import Image

from stress_dishes import STRESS

# Which region each dish belongs to, for the per-cuisine breakdown. Keyed by
# position in STRESS, which is grouped by region in source order.
REGIONS = [
    ("South Asian", 15),
    ("East Asian", 13),
    ("Southeast Asian", 13),
    ("Middle Eastern", 10),
    ("African", 10),
    ("Latin American", 11),
    ("European", 15),
    ("American", 8),
]


def slug(t):
    return t.replace(" ", "_").replace("(", "").replace(")", "").replace("/", "-")


def region_for(index):
    cursor = 0
    for name, count in REGIONS:
        if index < cursor + count:
            return name
        cursor += count
    return "Other"


def main():
    model = ct.models.MLModel("models/mobileclip_s0_image.mlpackage")
    meta = json.load(open("FoodVocabulary.json"))
    names, dims, food_count = meta["names"], meta["dimensions"], meta["foodCount"]
    matrix = np.fromfile("FoodVocabulary.bin", dtype=np.float16).reshape(-1, dims).astype(np.float32)

    per_region = {}
    rows = []
    abstained = 0

    for index, (title, accepted) in enumerate(STRESS.items()):
        path = f"stressimg/{slug(title)}.jpg"
        if not os.path.exists(path):
            continue

        try:
            im = Image.open(path).convert("RGB")
        except Exception:
            continue
        w, h = im.size
        s = min(w, h)
        im = im.crop(((w - s) // 2, (h - s) // 2, (w + s) // 2, (h + s) // 2)).resize((256, 256), Image.BICUBIC)

        emb = np.asarray(model.predict({"image": im})["final_emb_1"], np.float32).reshape(-1)
        emb /= np.linalg.norm(emb)
        sims = matrix @ emb

        order = np.argsort(-sims)[:5]
        guesses = [names[i] for i in order]
        best_nonfood = float(max(sims[food_count:]))
        top_food = float(sims[order[0]])

        # Mirror the app's rule exactly: below threshold, or beaten by a
        # non-food decoy, means the app shows nothing.
        would_abstain = top_food < 0.22 or top_food < best_nonfood
        if would_abstain:
            abstained += 1

        hit1 = guesses[0] in accepted
        hit5 = any(g in accepted for g in guesses)
        region = region_for(index)
        bucket = per_region.setdefault(region, {"n": 0, "t1": 0, "t5": 0})
        bucket["n"] += 1
        bucket["t1"] += hit1
        bucket["t5"] += hit5

        rows.append((region, title, hit1, hit5, would_abstain, guesses, top_food, best_nonfood))

    rows.sort(key=lambda r: (r[0], r[1]))
    current = None
    for region, title, hit1, hit5, abstain, guesses, top, nonfood in rows:
        if region != current:
            print(f"\n--- {region} ---")
            current = region
        mark = "OK  " if hit1 else ("top5" if hit5 else "MISS")
        flag = " [ABSTAIN]" if abstain else ""
        print(f"{mark} {title:24s} {top:.2f}  {', '.join(guesses[:3])}{flag}")

    total = len(rows)
    t1 = sum(r[2] for r in rows)
    t5 = sum(r[3] for r in rows)

    print("\n" + "=" * 62)
    print(f"{'region':<18}{'n':>4}{'top-1':>10}{'top-5':>10}")
    for name, _ in REGIONS:
        b = per_region.get(name)
        if not b:
            continue
        print(f"{name:<18}{b['n']:>4}{b['t1'] / b['n']:>9.0%}{b['t5'] / b['n']:>10.0%}")
    print("-" * 62)
    print(f"{'OVERALL':<18}{total:>4}{t1 / total:>9.0%}{t5 / total:>10.0%}")
    print(f"\nwould abstain (shows no guess): {abstained}/{total}")


if __name__ == "__main__":
    main()
