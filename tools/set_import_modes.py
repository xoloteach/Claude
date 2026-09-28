#!/usr/bin/env python3
"""Force web-friendly texture import settings (lossy WebP + mipmaps) for all photo textures.
Keeps UI / FX sprites / decals lossless. Run after adding new textures, then re-import."""
import pathlib, re
root = pathlib.Path(__file__).resolve().parent.parent
keep_lossless = ("assets/textures/fx/", "assets/textures/ui/", "assets/textures/decals/")
changed = 0
for imp in root.glob("assets/**/*.import"):
    src = str(imp.relative_to(root))[:-len(".import")]
    if not src.lower().endswith((".jpg", ".jpeg", ".png", ".webp")):
        continue
    txt = imp.read_text()
    if 'importer="texture"' not in txt:
        continue
    lossless = src.startswith(keep_lossless)
    new = txt
    new = re.sub(r"compress/mode=\d+", "compress/mode=%d" % (0 if lossless else 1), new)
    new = re.sub(r"compress/lossy_quality=[\d.]+", "compress/lossy_quality=0.82", new)
    new = re.sub(r"mipmaps/generate=\w+", "mipmaps/generate=true", new)
    new = re.sub(r"detect_3d/compress_to=\d+", "detect_3d/compress_to=0", new)
    if new != txt:
        imp.write_text(new)
        changed += 1
print(f"updated {changed} import files")
