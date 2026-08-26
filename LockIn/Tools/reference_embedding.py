"""Reference embedding for a deterministic synthetic image.

The Swift test builds the identical image and must produce the same vector.
This is what catches a BGRA/RGB channel swap in the Swift preprocessing —
a bug that would otherwise be invisible without a camera to test against.
"""
import json
import numpy as np, coremltools as ct
from PIL import Image

SIDE = 256
# Deliberately asymmetric across channels: if R and B were swapped, the
# embedding changes. A grey gradient would hide exactly that bug.
arr = np.zeros((SIDE, SIDE, 3), dtype=np.uint8)
for y in range(SIDE):
    for x in range(SIDE):
        arr[y, x] = (x, y // 2, (x * y) // 512)

img = Image.fromarray(arr, "RGB")
img.save("synthetic_reference.png")

m = ct.models.MLModel("models/mobileclip_s0_image.mlpackage")
e = np.asarray(m.predict({"image": img})["final_emb_1"], np.float32).reshape(-1)
e /= np.linalg.norm(e)

json.dump({"embedding": [round(float(v), 6) for v in e]}, open("reference_embedding.json", "w"))
print("dims:", e.shape[0])
print("first 8:", [round(float(v), 4) for v in e[:8]])
