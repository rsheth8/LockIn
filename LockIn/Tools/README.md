# Food recognition build tools

Build-time only. None of this ships in the app — it produces the two small
files the app *does* bundle:

- `Sources/Resources/FoodVocabulary.bin` — float16 text embeddings (~700 KB)
- `Sources/Resources/FoodVocabulary.json` — the matching names

The app also bundles `Sources/Resources/FoodImageEncoder.mlpackage`
(Apple's MobileCLIP-S0 image encoder, ~22 MB), which Xcode compiles to
`.mlmodelc` at build time.

## When you'd run this

Only when changing the vocabulary — e.g. adding a cuisine or a dish the
classifier keeps missing. Edit `food_vocabulary.py`, re-run the build, and
commit the regenerated `.bin`/`.json`.

## Setup

```bash
uv venv --python 3.11 clipenv
uv pip install --python clipenv/bin/python coremltools numpy pillow transformers
```

Then fetch both MobileCLIP encoders into `models/` (the text encoder is ~85 MB
and is needed *only* here — precomputing is exactly why the app doesn't ship
it):

```bash
BASE=https://huggingface.co/apple/coreml-mobileclip/resolve/main
for m in mobileclip_s0_image mobileclip_s0_text; do
  mkdir -p "models/$m.mlpackage/Data/com.apple.CoreML/weights"
  curl -L "$BASE/$m.mlpackage/Manifest.json" -o "models/$m.mlpackage/Manifest.json"
  curl -L "$BASE/$m.mlpackage/Data/com.apple.CoreML/model.mlmodel" -o "models/$m.mlpackage/Data/com.apple.CoreML/model.mlmodel"
  curl -L "$BASE/$m.mlpackage/Data/com.apple.CoreML/weights/weight.bin" -o "models/$m.mlpackage/Data/com.apple.CoreML/weights/weight.bin"
done
```

## Build

```bash
./clipenv/bin/python build_food_vocabulary.py
cp FoodVocabulary.bin FoodVocabulary.json ../Sources/Resources/
```

## Evaluate

`eval_food_recognition.py` scores real dish photos against the full vocabulary.
It needs test images in `testimg/` named after the dishes in its `ACCEPT` map.

Last run: **81% top-1, 95% top-5** across 21 photos spanning South Asian, East
and Southeast Asian, Middle Eastern, African, European and Latin American
dishes. Non-food decoys scored 0.13–0.19 against correct-food matches of
0.26–0.35, which is where `FoodVisionClassifier.minimumUsableScore` (0.22)
comes from.

## The one real gotcha

**Text padding must be zeros.** OpenAI's reference `clip.tokenize()` pads to 77
tokens with `0`; HuggingFace's `padding="max_length"` pads with the EOT id
(`49407`) instead. MobileCLIP was never trained to see EOT in those positions,
and the resulting embeddings are close to noise — measured here, correct-label
similarity collapsed from ~0.30 to ~0.06 and ranking became random (0/5 top-1
vs 8/8 with zero padding). This is silent: nothing errors, the numbers just
quietly stop meaning anything.
