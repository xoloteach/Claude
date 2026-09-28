#!/usr/bin/env python3
"""QA helper: print loudness envelope + band balance for audio files.
usage: python3 tools/audio/metrics.py files...
"""
import sys
import numpy as np
import soundfile as sf
from scipy import signal

WIN = [(0, 0.01), (0.03, 0.08), (0.1, 0.2), (0.25, 0.35), (0.5, 0.6), (0.9, 1.0), (1.4, 1.5), (1.9, 2.0)]


def band(x, sr, lo, hi):
    sos = signal.butter(4, [lo / (sr / 2), min(hi, sr / 2 * 0.99) / (sr / 2)], "bandpass", output="sos")
    return signal.sosfilt(sos, x)


for f in sys.argv[1:]:
    x, sr = sf.read(f, always_2d=True)
    m = x.mean(1)
    ref = np.sqrt(np.mean(m[: int(0.3 * sr)] ** 2)) + 1e-12
    env = []
    for a, b in WIN:
        s = m[int(a * sr):int(b * sr)]
        env.append("  -  " if len(s) == 0 else f"{20*np.log10(np.sqrt(np.mean(s**2))+1e-12):5.0f}")
    tot = np.sum(m ** 2) + 1e-12
    bands = [(20, 120), (120, 500), (500, 2000), (2000, 6000), (6000, 18000)]
    bb = [f"{10*np.log10(np.sum(band(m, sr, lo, hi)**2)/tot+1e-12):5.1f}" for lo, hi in bands]
    clip = int(np.sum(np.abs(x) > 0.999))
    print(f"{f.split('/')[-1]:24s} dur {len(m)/sr:5.2f} pk {20*np.log10(np.abs(x).max()):5.1f} "
          f"rms300 {20*np.log10(ref):5.1f} | env {' '.join(env)} | bands(sub,low,mid,pres,air) {' '.join(bb)} "
          f"| dc {x.mean():+.4f} clip {clip}")
