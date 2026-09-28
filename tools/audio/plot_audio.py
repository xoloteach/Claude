#!/usr/bin/env python3
"""QA helper: render waveform + spectrogram sheets for audio files.

usage: python3 tools/audio/plot_audio.py OUT.png file1.wav [file2.wav ...] [--tmax 2.5] [--seg start:dur]
"""
import sys
import numpy as np
import soundfile as sf
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy import signal


def main():
    args = sys.argv[1:]
    tmax = None
    seg = None
    if "--tmax" in args:
        i = args.index("--tmax"); tmax = float(args[i + 1]); del args[i:i + 2]
    if "--seg" in args:
        i = args.index("--seg"); a, b = args[i + 1].split(":"); seg = (float(a), float(b)); del args[i:i + 2]
    out, files = args[0], args[1:]
    n = len(files)
    fig, axes = plt.subplots(n, 2, figsize=(14, 2.1 * n), squeeze=False,
                             gridspec_kw={"width_ratios": [1, 1.3]})
    for r, f in enumerate(files):
        x, sr = sf.read(f, always_2d=True)
        if seg:
            x = x[int(seg[0] * sr):int((seg[0] + seg[1]) * sr)]
        if tmax:
            x = x[:int(tmax * sr)]
        m = x.mean(1)
        t = np.arange(len(m)) / sr
        pk = 20 * np.log10(np.abs(x).max() + 1e-12)
        rms = 20 * np.log10(np.sqrt((m ** 2).mean()) + 1e-12)
        dc = x.mean()
        ax = axes[r, 0]
        for c in range(x.shape[1]):
            ax.plot(t, x[:, c], lw=0.4, alpha=0.8)
        ax.set_ylim(-1.05, 1.05)
        ax.set_title(f"{f.split('/')[-1]}  {len(m)/sr:.2f}s ch{x.shape[1]} pk{pk:.1f} rms{rms:.1f} dc{dc:.4f}", fontsize=8)
        ax.tick_params(labelsize=6)
        ax = axes[r, 1]
        nper = 1024 if len(m) > 4096 else 256
        fr, tt, S = signal.spectrogram(m, sr, nperseg=nper, noverlap=nper * 3 // 4)
        S = 10 * np.log10(S + 1e-14)
        ax.pcolormesh(tt, fr, S, vmin=S.max() - 90, vmax=S.max(), shading="auto", cmap="magma")
        ax.set_yscale("symlog", linthresh=200)
        ax.set_ylim(20, sr / 2)
        ax.tick_params(labelsize=6)
    plt.tight_layout()
    plt.savefig(out, dpi=70)


if __name__ == "__main__":
    main()
