#!/usr/bin/env python3
"""Split Resources/OpenSnap.png into Liquid Glass icon layer masks.

Icon Composer layers are recoloured by icon.json fills, so each layer is a
white mask: the blue dollar and the dark shield. The logo's baked gloss,
white outline and drop shadow are dropped; the system supplies its own.
"""
import sys
from pathlib import Path
from PIL import Image, ImageFilter

root = Path(__file__).resolve().parent.parent
source = Image.open(root / "Resources/OpenSnap.png").convert("RGBA")
assets = root / "Resources/OpenSnap.icon/Assets"
assets.mkdir(parents=True, exist_ok=True)

def mask(keep, opacity):
    out = Image.new("L", source.size, 0)
    out.putdata([a if a >= opacity and keep(r, g, b) else 0 for r, g, b, a in source.get_flattened_data()])
    # Close pinholes left by the gloss highlight, then restore soft edges.
    out = out.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    return out.filter(ImageFilter.GaussianBlur(0.8))

layers = {
    "dollar": mask(lambda r, g, b: b > r + 25 and b > 90, 129),
    # The baked drop shadow is near-black at ~75% opacity; the shield is opaque black.
    "shield": mask(lambda r, g, b: max(r, g, b) < 30, 240),
}
for name, alpha in layers.items():
    layer = Image.new("RGBA", source.size, (255, 255, 255, 0))
    layer.putalpha(alpha)
    layer.save(assets / f"{name}.png", optimize=True)
    print(name, alpha.getbbox(), file=sys.stderr)
