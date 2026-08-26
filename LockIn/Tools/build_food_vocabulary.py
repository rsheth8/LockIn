"""Precompute MobileCLIP text embeddings for the food vocabulary.

Build-time only — the app never runs a text encoder. This produces two small
files that get bundled instead:

  FoodVocabulary.json  - ordered list of names (+ where the food half ends)
  FoodVocabulary.bin   - L2-normalised float16 embeddings, row-per-name

At runtime the app embeds a photo with the image encoder and takes a dot
product against these rows, which is cosine similarity given both sides are
normalised.
"""

import json
import struct

import numpy as np
import coremltools as ct
from transformers import AutoTokenizer

from food_vocabulary import (FOOD_NAMES, NON_FOOD, SOUTH_ASIAN, EAST_ASIAN,
                             SOUTHEAST_ASIAN, MIDDLE_EASTERN_AND_AFRICAN,
                             EUROPEAN, AMERICAS)

# Prompt ensembling: averaging a few phrasings is standard CLIP practice and
# measurably beats a single template, because it averages out quirks of any
# one caption style.
FOOD_TEMPLATES = [
    "a photo of {}, a type of food.",
    "a close-up photo of {}.",
    "a photo of a plate of {}.",
    "a photo of {} on a table.",
]
NON_FOOD_TEMPLATES = [
    "a photo of {}.",
    "a close-up photo of {}.",
]

CONTEXT_LENGTH = 77


def encode_batch(model, tokenizer, prompts):
    """Run prompts through the text encoder, one at a time (the CoreML model
    is compiled for batch size 1).

    Padding must be ZEROS, matching OpenAI's reference `clip.tokenize()`.
    HuggingFace's `padding="max_length"` pads with the EOT id (49407) instead,
    which this model was never trained to see in those positions — it produces
    near-random embeddings (verified: correct-label similarity collapses from
    ~0.30 to ~0.06, and ranking degrades to noise).
    """
    out = []
    for prompt in prompts:
        ids = tokenizer(prompt)["input_ids"][:CONTEXT_LENGTH]
        ids = ids + [0] * (CONTEXT_LENGTH - len(ids))
        arr = np.array([ids], dtype=np.int32)
        emb = model.predict({"text": arr})["final_emb_1"]
        out.append(np.asarray(emb, dtype=np.float32).reshape(-1))
    return np.stack(out)


def embed_names(model, tokenizer, names, templates):
    rows = []
    for i, name in enumerate(names):
        embs = encode_batch(model, tokenizer, [t.format(name) for t in templates])
        # Normalise each template's embedding before averaging, so a single
        # large-magnitude phrasing can't dominate the ensemble.
        embs /= np.linalg.norm(embs, axis=1, keepdims=True)
        mean = embs.mean(axis=0)
        mean /= np.linalg.norm(mean)
        rows.append(mean)
        if (i + 1) % 50 == 0:
            print(f"  {i + 1}/{len(names)}")
    return np.stack(rows)


def main():
    print("loading text encoder...")
    model = ct.models.MLModel("models/mobileclip_s0_text.mlpackage")
    tokenizer = AutoTokenizer.from_pretrained("openai/clip-vit-base-patch32")

    print(f"embedding {len(FOOD_NAMES)} food names...")
    food = embed_names(model, tokenizer, FOOD_NAMES, FOOD_TEMPLATES)
    print(f"embedding {len(NON_FOOD)} non-food names...")
    nonfood = embed_names(model, tokenizer, NON_FOOD, NON_FOOD_TEMPLATES)

    matrix = np.concatenate([food, nonfood]).astype(np.float16)
    names = FOOD_NAMES + NON_FOOD

    with open("FoodVocabulary.bin", "wb") as f:
        f.write(matrix.tobytes())

    # Entries before dishCount are composed dishes; the rest are single
    # ingredients. That split decides which nutrition source to try first —
    # label databases are built around ingredients and packaged goods, while
    # a cooked dish needs a source that estimates from the dish name.
    dish_count = len(SOUTH_ASIAN + EAST_ASIAN + SOUTHEAST_ASIAN
                     + MIDDLE_EASTERN_AND_AFRICAN + EUROPEAN + AMERICAS)

    meta = {
        "names": names,
        "foodCount": len(FOOD_NAMES),
        "dishCount": dish_count,
        "dimensions": int(matrix.shape[1]),
        "model": "mobileclip_s0",
    }
    with open("FoodVocabulary.json", "w") as f:
        json.dump(meta, f, separators=(",", ":"))

    print(f"\nwrote {matrix.shape[0]} x {matrix.shape[1]} float16")
    print(f"  bin  {matrix.nbytes / 1024:.0f} KB")

    # Sanity check: nearest neighbours of a couple of names should be
    # semantically adjacent, not random.
    m32 = matrix.astype(np.float32)
    for probe in ["palak paneer", "cheeseburger", "sushi rolls"]:
        idx = names.index(probe)
        sims = m32 @ m32[idx]
        top = np.argsort(-sims)[1:5]
        print(f"  {probe!r} -> {[names[t] for t in top]}")


if __name__ == "__main__":
    main()
