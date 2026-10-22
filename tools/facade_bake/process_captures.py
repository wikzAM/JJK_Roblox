"""Turn straight-on Studio captures of ground facade designs (magenta backdrop) into
flat skin textures.

Each capture shows one gallery design (17 studs tall, ~4.5 studs of footing below grade).
We keep the top 15.5 studs (12.5 above grade + 3 below), pad the top with wall colour so
the tile covers a full 17.86-stud storey plus the 3-stud below-grade skirt, fill glass
gaps that show the backdrop, and write:
  out/<name>.png       preview
  out/<name>.rgba.b64  raw RGBA, base64, for Studio's EditableImage loader
  out/contact_sheet.png

Usage: python -I process_captures.py <captures.json> <out_dir>
captures.json: [{"name": "01_Konbini", "width": 36, "file": "...jpg"}, ...]
"""
import base64
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

PPS = 8  # pixels per stud in the output
DESIGN_H = 17.0
KEEP_TOP = 15.5
STOREY = 17.86
PAD_TOP = STOREY - 12.5


def magenta_mask(a):
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    return (r > 170) & (b > 170) & (g < 110)


def process(entry, out_dir):
    img = np.asarray(Image.open(entry["file"]).convert("RGB"))
    mask = magenta_mask(img)
    solid = ~mask
    rows = np.where(solid.mean(axis=1) > 0.3)[0]
    cols = np.where(solid.mean(axis=0) > 0.3)[0]
    y0, y1, x0, x1 = rows[0], rows[-1] + 1, cols[0], cols[-1] + 1
    crop = img[y0:y1, x0:x1].copy()
    cmask = mask[y0:y1, x0:x1]
    # Backdrop seen through glass edges: replace with a dark glass tone.
    crop[cmask] = (34, 44, 46)
    h_px = crop.shape[0]
    keep = int(round(h_px * KEEP_TOP / DESIGN_H))
    crop = crop[:keep]
    w_out = int(round(entry["width"] * PPS))
    h_keep = int(round(KEEP_TOP * PPS))
    face = Image.fromarray(crop).resize((w_out, h_keep), Image.LANCZOS)
    # Pad above with plain wall: tile a 2x2-stud concrete patch from the bottom-left
    # (below-grade plinth), so signs and glass never repeat into the padding.
    pad_px = int(round(PAD_TOP * PPS))
    arr = np.asarray(face)
    band = arr[-2 * PPS :, w_out // 4 : 3 * w_out // 4].reshape(-1, 3)
    base = np.median(band, axis=0)
    rng = np.random.default_rng(len(entry["name"]))
    noise = rng.normal(0, 5, (pad_px, w_out, 1))
    pad = np.clip(base[None, None, :] * 0.95 + noise, 0, 255).astype(np.uint8)
    pad[-2:] = (pad[-2:].astype(float) * 0.6).astype(np.uint8)  # shadow line above the fascia
    full = np.concatenate([pad, arr], axis=0)
    out = Image.fromarray(full)
    out.save(os.path.join(out_dir, entry["name"] + ".png"))
    rgba = np.concatenate([full, np.full(full.shape[:2] + (1,), 255, np.uint8)], axis=2)
    with open(os.path.join(out_dir, entry["name"] + ".rgba.b64"), "w") as f:
        f.write(base64.b64encode(rgba.tobytes()).decode("ascii"))
    return entry["name"], out.size


def main():
    entries = json.load(open(sys.argv[1]))
    out_dir = sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    sizes = {}
    previews = []
    for e in entries:
        name, size = process(e, out_dir)
        sizes[name] = {"w": size[0], "h": size[1], "studsW": e["width"], "studsH": STOREY + 3}
        previews.append(Image.open(os.path.join(out_dir, name + ".png")))
    json.dump(sizes, open(os.path.join(out_dir, "index.json"), "w"), indent=1)
    # Contact sheet, 3 columns.
    cell_w = max(p.size[0] for p in previews) + 20
    cell_h = max(p.size[1] for p in previews) + 34
    cols = 3
    rows = (len(previews) + cols - 1) // cols
    sheet = Image.new("RGB", (cell_w * cols, cell_h * rows), (24, 24, 28))
    d = ImageDraw.Draw(sheet)
    for i, (e, p) in enumerate(zip(entries, previews)):
        cx, cy = (i % cols) * cell_w + 10, (i // cols) * cell_h + 26
        sheet.paste(p, (cx, cy))
        d.text((cx, cy - 18), e["name"], fill=(230, 230, 230))
    sheet.save(os.path.join(out_dir, "contact_sheet.png"))
    print(json.dumps(sizes))


if __name__ == "__main__":
    main()
