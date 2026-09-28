"""Download + cache the CC0 source recordings used by gen_sfx.py.

Everything here is CC0 / public domain (see assets/audio/CREDITS.md).
Cache dir: $IRONLINE_AUDIO_CACHE or /tmp/ironline_audio_src
"""
import os
import glob
import zipfile
import urllib.request
from functools import lru_cache

import numpy as np
import soundfile as sf

from dsp import resample_to

CACHE = os.environ.get("IRONLINE_AUDIO_CACHE", "/tmp/ironline_audio_src")
OGA = "https://opengameart.org/sites/default/files/"

# name -> (url, archive type)
SOURCES = {
    # The Free Firearm Sound Library (Still North Media) - CC0, 96 kHz/24-bit real outdoor gunshot recordings
    "firearm": (OGA + "Prepared%20SFX%20Library.7z", "7z"),
    # Kenney CC0 packs
    "kenney_impact": ("https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip", "zip"),
    "kenney_interface": ("https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip", "zip"),
    # OpenGameArt CC0 foley
    "oga_ar_reload": (OGA + "assaultriflereload1_0.wav", "file"),    # SpringySpringo "Gun reload sounds"
    "oga_gun_reload": (OGA + "gunreload1.wav", "file"),              # SpringySpringo
    "oga_shotgun_cock": (OGA + "shotguncock_0.wav", "file"),         # SpringySpringo
    "oga_handgun_reload": (OGA + "reload.wav", "file"),              # zer0_sol "Handgun Reload Sound Effect"
    "oga_clipload1": (OGA + "clipload1.wav", "file"),                # BMacZero "Gun Reload Sound Effects"
    "oga_clipload2": (OGA + "clipload2.wav", "file"),
    "oga_singlebullet": (OGA + "singlebullet1.wav", "file"),
    "oga_shotgun_reload": (OGA + "shotgunsounds.zip", "zip"),        # zer0_sol "Shotgun Reload Sound effects"
}


def _download(url, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    tmp = dst + ".part"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (ironline-audio-build)"})
    with urllib.request.urlopen(req, timeout=600) as r, open(tmp, "wb") as f:
        while True:
            b = r.read(1 << 20)
            if not b:
                break
            f.write(b)
    os.replace(tmp, dst)


def fetch(name):
    url, kind = SOURCES[name]
    base = os.path.join(CACHE, name)
    if kind == "file":
        dst = base + os.path.splitext(url)[1]
        if not os.path.exists(dst):
            print("  downloading", name)
            _download(url, dst)
        return dst
    done = base + "/.ok"
    if os.path.exists(done):
        return base
    arc = base + "." + kind
    if not os.path.exists(arc):
        print("  downloading", name, "(may take a while)")
        _download(url, arc)
    os.makedirs(base, exist_ok=True)
    if kind == "zip":
        with zipfile.ZipFile(arc) as z:
            z.extractall(base)
    else:
        import py7zr  # pip install py7zr
        with py7zr.SevenZipFile(arc) as z:
            z.extractall(base)
    open(done, "w").close()
    return base


def fetch_all():
    for k in SOURCES:
        fetch(k)


@lru_cache(maxsize=None)
def _load(path):
    x, sr = sf.read(path, always_2d=True, dtype="float64")
    x = resample_to(x, sr)
    x = x - x.mean(0)
    return x


def load(path, st=None):
    """Load file -> float64 at 44.1 kHz. st=None keep, True stereo, False mono."""
    x = _load(path).copy()
    if st is False:
        return x.mean(1)
    if st is True:
        return x if x.shape[1] == 2 else np.repeat(x, 2, 1)
    return x[:, 0] if x.shape[1] == 1 else x


def firearm(folder, fname, st=True):
    base = fetch("firearm")
    p = glob.glob(os.path.join(base, "*", folder, fname))[0]
    return load(p, st)


def kenney(fname, st=False):
    for pack in ("kenney_impact", "kenney_interface"):
        base = fetch(pack)
        hits = glob.glob(os.path.join(base, "**", fname), recursive=True)
        if hits:
            return load(hits[0], st)
    raise FileNotFoundError(fname)


def oga(name, st=False, sub=None):
    p = fetch(name)
    if sub:
        p = glob.glob(os.path.join(p, "**", sub), recursive=True)[0]
    return load(p, st)
