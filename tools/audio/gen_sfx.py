#!/usr/bin/env python3
"""IRONLINE sound-effect generator.

Regenerates every file in assets/audio/sfx/ from CC0 source recordings (downloaded to
$IRONLINE_AUDIO_CACHE, default /tmp/ironline_audio_src) + numpy/scipy synthesis/processing.

    python3 tools/audio/gen_sfx.py            # everything
    python3 tools/audio/gen_sfx.py ar_fire hitmarker   # only these bases

Requires: numpy scipy soundfile py7zr  (pip install soundfile py7zr)
Deterministic: every sound uses an RNG seeded from its file name.
"""
import os
import sys
import zlib
import time

import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from dsp import *            # noqa: E402,F401,F403
import sources as S          # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "sfx")

REG = []   # (base, count, func, opts)


def sfx(base, n=1, st=False, peak=-1.0, fmt="wav", fin=0.0, fout=0.03, trim_db=-66.0, lead=True):
    loop = base.startswith(("amb_", "music_"))
    def deco(fn):
        REG.append((base, n, fn, dict(st=st, peak=peak, fmt=fmt, fin=fin, fout=fout, trim_db=trim_db, lead=lead,
                                      loop=loop)))
        return fn
    return deco


def rng_for(name):
    return np.random.default_rng(zlib.crc32(name.encode()))


def finalize(x, o):
    x = np.nan_to_num(x)
    if not o["loop"]:          # (an IIR at the loop seam would break seamlessness)
        x = dcblock(x, 16.0)
    if o["st"]:
        x = stereo(x)
    else:
        x = mono(x)
    if o["trim_db"] is not None:
        x = trim(x, o["trim_db"], lead=o["lead"], fout=o["fout"])
    else:
        x = fade(x, 0, o["fout"])
    if o["fin"] > 0:
        x = fade(x, o["fin"], 0)
    x = normalize(x, o["peak"])
    return np.clip(x, -1.0, 1.0)


def write(path, x, fmt):
    if fmt == "ogg":
        sf.write(path, x.astype(np.float32), SR, format="OGG", subtype="VORBIS")
    else:
        sf.write(path, x, SR, subtype="PCM_16")


# =============================================================================== shared layers
def metal_clack(i=0, pitch=1.0, hpf=1500.0, dur=0.06, rng=None):
    """Short mechanical metal 'clack' from Kenney impact recordings (bolt carrier, slide...)."""
    names = ["impactMetal_light_000.ogg", "impactMetal_light_001.ogg", "impactMetal_light_002.ogg",
             "impactMetal_light_003.ogg", "impactMetal_light_004.ogg", "impactPlate_light_000.ogg",
             "impactPlate_light_001.ogg", "impactPlate_light_002.ogg"]
    x = S.kenney(names[i % len(names)])
    x = first_hit(x, 0.0005)
    x = resample_ratio(x, pitch)
    x = hp(x, hpf, 2)[: secs(dur)]
    return fade(normalize(x, 0), 0, dur * 0.5)


def dry_crack(dur=0.02, lo=2500, hi=14000, tau=0.0025, rng=None):
    return burst(dur, lo, hi, tau, rng, att=0.00008)


def outdoor_ir(rng, dur=1.6, rt_lo=1.4, rt_hi=0.45, refl=None, diffuse_db=0.0, predelay=0.0, refl_lp=3000.0):
    if refl is None:
        refl = [(0.085, -6, -0.6), (0.14, -9, 0.7), (0.23, -11, -0.3), (0.36, -14, 0.5), (0.55, -19, -0.7),
                (0.8, -25, 0.2)]
    return make_ir(dur, rt_lo, rt_hi, 1200.0, predelay, refl, refl_lp, diffuse_db, rng, st=True)


def gunshot(shot, rng, *, dur=1.6, thump=(140, 55, 0.025, 0.07), thump_db=-4.0, thump_drive=2.0,
            crack_db=-6.0, crack_tau=0.004, low_shelf=(110, 5.0), mud=(350, -3.0), presence=(3200, 2.5),
            mech=(), tail_ir=None, tail_db=-8.0, tail_src_ms=70, natural=None, natural_db=-10.0,
            comp=(-26, 4.0, 1.0, 120), drive=1.6, hpf=32.0, lpf=None, extra=(), spike_drive=5.0):
    """Layered player-weapon shot:  real recording (EQ'd)  + transient crack  + sub thump
    + mechanical action  + synthetic slap-back environment  (+ optional distant natural tail)."""
    n = secs(dur)
    body = pad(shot, n)
    body = hp(body, hpf, 2)
    body = shelf(body, low_shelf[0], low_shelf[1], "low")
    body = peq(body, mud[0], mud[1], 0.9)
    body = peq(body, presence[0], presence[1], 0.8)
    if lpf:
        body = lp(body, lpf, 2)
    # the raw report is a ~1 ms spike (~25 dB crest); saturate it so the body has weight + grit
    body = normalize(softclip(normalize(body, 0) * spike_drive, 1.0), 0)
    layers = [(body, 0.0, 0.0)]
    # transient crack (from the recording itself -> keeps its character)
    cr = hp(body[: secs(0.05)], 2800, 2) * expenv(secs(0.05), crack_tau, 0.0)[:, None]
    layers.append((cr, 0.0, crack_db))
    if natural is not None:
        layers.append((normalize(natural, 0), 0.0, natural_db))
    x = mix(*layers, n=n)
    # squash the recording's spike so the body/tail read loud (the 'wall' of a modern FPS shot)
    x = normalize(x, 0)
    x = compress(x, comp[0], comp[1], comp[2], comp[3], 6.0)
    x = normalize(x, 0)
    # environment: synthetic slap-back tail fed by the first ms of the (compressed) report
    post = []
    if tail_ir is not None:
        src = x[: secs(tail_src_ms / 1000)]
        src = fade(lp(src, 6500, 2), 0, 0.02)
        tl = convolve(src, tail_ir)
        tl = tl / (np.sqrt(np.mean(tl ** 2)) + 1e-12) * np.sqrt(np.mean(x[: secs(0.25)] ** 2))
        post.append((tl, 0.0, tail_db))
    # sub/low body thump (40-150 Hz), saturated, added after compression so it stays tight
    f0, f1, tf, ta = thump
    th = thump_fn(0.5, f0, f1, tf, ta, drive=thump_drive)
    post.append((stereo(th), 0.0008, thump_db))
    for (t, db, idx, pitch) in mech:
        post.append((stereo(metal_clack(idx, pitch)), t, db))
    for e in extra:
        post.append(e)
    x = mix((x, 0, 0), *post, n=n)
    x = normalize(x, 0)
    x = softclip(x, drive)
    return x


def thump_fn(dur, f0, f1, tau_f, tau_a, drive=1.0):
    x = thump(dur, f0, f1, tau_f, tau_a, 0.0012, drive)
    return lp(x, 400, 2)


def shots_of(folder, fname, min_gap=1.5):
    x = S.firearm(folder, fname)
    return x, onsets(x, -14, 10, min_gap)


def take(folder, fname, k, dur, pre=0.002, ratio=1.0):
    x, on = shots_of(folder, fname)
    seg = slice_at(x, on[k % len(on)], pre, dur / ratio + 0.05)
    return resample_ratio(seg, ratio)


# =============================================================================== player weapons
@sfx("ar_fire", 4, st=True, peak=-1.0, trim_db=-62)
def ar_fire(i, rng):
    src = [("AR-15", "D_32P.wav", 0, 1.00), ("AR-15", "D_32P.wav", 1, 1.03),
           ("Savage 10 .300 Blackout", "T_27P.wav", 0, 1.06), ("AR-15", "D_32P.wav", 0, 0.965)][i]
    shot = take(src[0], src[1], src[2], 1.7, ratio=src[3])
    nat = take("AR-15", "D_24P.wav", i % 2, 1.7)
    nat = lp(hp(nat, 150), 5000)
    ir = outdoor_ir(rng, dur=1.5, rt_lo=1.3, rt_hi=0.4)
    return gunshot(shot, rng, dur=1.7, thump=(150 + 10 * i, 60, 0.018, 0.04), thump_db=-7.0, spike_drive=7.0,
                   crack_db=-5.0, mech=[(0.028, -20, i, 1.25), (0.062, -26, i + 3, 1.1)],
                   tail_ir=ir, tail_db=-1.0, natural=nat, natural_db=-12.0, drive=1.7)


@sfx("smg_fire", 4, st=True, peak=-1.0, trim_db=-60)
def smg_fire(i, rng):
    """Suppressed 9mm: the report is choked -> low 'thup', gas hiss, loud bolt mechanics, short tail."""
    dur = 0.55
    n = secs(dur)
    shot = take("Carl Gustav M45", "G_31P.wav", i % 3, 0.4, ratio=[1.0, 1.04, 0.97, 1.02][i])
    # suppressed report: heavily low-passed and gated recording
    rep = lp(lp(shot, 1400, 2), 2200, 2) * expenv(len(shot), 0.028, 0.0)[:, None]
    rep = shelf(rep, 160, 5, "low")
    # the 'thup': low mid pressure pop
    pop = thump(0.25, 260, 85, 0.012, 0.03, 0.0008, 2.5)
    pop = lp(pop, 900, 2)
    # gas escaping from the can
    hiss = burst(0.12, 1800, 7000, 0.018, rng, att=0.001, st=True)
    # bolt: back (right at shot) + forward slam
    bolt1 = metal_clack(i, 1.4, 900, 0.05)
    bolt2 = metal_clack(i + 5, 1.1, 700, 0.06)
    body = thump(0.3, 120, 60, 0.02, 0.05, 0.001, 1.8)
    ir = outdoor_ir(rng, dur=0.5, rt_lo=0.45, rt_hi=0.18,
                    refl=[(0.05, -10, -0.5), (0.09, -14, 0.6), (0.15, -19, 0.0)], refl_lp=2500)
    tl = convolve(fade(rep[: secs(0.05)], 0, 0.01), ir)
    rep = hp(rep, 140, 2)
    x = mix((rep, 0, -1), (stereo(pop), 0.0005, -8), (hiss, 0.0, -13), (stereo(bolt1), 0.004, -5),
            (stereo(bolt2), 0.047 + 0.004 * i, -7), (stereo(body), 0.001, -13),
            (tl / (np.abs(tl).max() + 1e-9), 0, -14), n=n)
    x = normalize(x, 0)
    x = compress(x, -20, 3.0, 1.5, 60, 6)
    x = softclip(normalize(x, 0), 1.4)
    return x


@sfx("shotgun_fire", 3, st=True, peak=-1.0, trim_db=-62)
def shotgun_fire(i, rng):
    src = [("Mossberg", "N_30P.wav", 0), ("Model 12", "K_22P.wav", 0), ("Nova", "O_21P.wav", 0)][i]
    shot = take(src[0], src[1], src[2], 2.2, ratio=[0.96, 0.98, 0.95][i])
    nat = take("Mossberg", "N_26P.wav", i, 2.2)
    nat = lp(hp(nat, 90), 4000)
    ir = outdoor_ir(rng, dur=2.0, rt_lo=1.8, rt_hi=0.55,
                    refl=[(0.095, -5, -0.6), (0.16, -8, 0.7), (0.26, -10, -0.2), (0.41, -13, 0.5),
                          (0.62, -16, -0.6), (0.9, -21, 0.3), (1.25, -26, -0.2)])
    # deep boom: two thumps (sub + low-mid punch)
    extra = [(stereo(thump_fn(0.6, 95, 42, 0.04, 0.085, 2.2)), 0.002, -9.0)]
    return gunshot(shot, rng, dur=2.2, thump=(190, 65, 0.016, 0.045), thump_db=-6.0, spike_drive=6.0, thump_drive=2.5,
                   crack_db=-8.0, crack_tau=0.005, low_shelf=(95, 6.5), mud=(420, -3.5), presence=(2500, 1.5),
                   mech=[(0.03, -24, i + 1, 0.9)], tail_ir=ir, tail_db=0.0, tail_src_ms=90,
                   natural=nat, natural_db=-13, comp=(-26, 4.0, 1.0, 160), drive=1.9, extra=extra)


@sfx("pistol_fire", 3, st=True, peak=-1.0, trim_db=-62)
def pistol_fire(i, rng):
    src = [("Walther PPQ", "X_39P.wav", 0, 1.0), ("Walther PPQ", "X_39P.wav", 1, 1.02),
           ("1911", "A_42P.wav", 0, 1.03)][i]
    shot = take(src[0], src[1], src[2], 1.3, ratio=src[3])
    ir = outdoor_ir(rng, dur=1.2, rt_lo=1.0, rt_hi=0.35,
                    refl=[(0.08, -7, -0.6), (0.13, -10, 0.7), (0.22, -13, -0.2), (0.34, -16, 0.4), (0.52, -20, 0.0)])
    # slide cycling: sharp slide-back + return
    return gunshot(shot, rng, dur=1.3, thump=(170, 80, 0.015, 0.03), thump_db=-9.0, spike_drive=7.0, crack_db=-4.0,
                   crack_tau=0.003, low_shelf=(130, 4.0), presence=(3500, 3.0),
                   mech=[(0.012, -17, i + 2, 1.5), (0.045, -20, i + 4, 1.3)],
                   tail_ir=ir, tail_db=-3.0, drive=1.6)


@sfx("sniper_fire", 2, st=True, peak=-1.0, trim_db=-64)
def sniper_fire(i, rng):
    src = [("Mosin Nagant", "M_21P.wav", 0, 0.97), ("1917", "B_24P.wav", 0, 0.96)][i]
    shot = take(src[0], src[1], src[2], 2.8, ratio=src[3])
    nat = take("Mosin Nagant", "M_26P.wav", i, 2.8)
    nat = lp(hp(nat, 80), 3500)
    ir = outdoor_ir(rng, dur=2.6, rt_lo=2.2, rt_hi=0.6,
                    refl=[(0.11, -4, -0.7), (0.19, -7, 0.7), (0.31, -9, -0.2), (0.48, -11, 0.5), (0.72, -14, -0.6),
                          (1.02, -19, 0.3), (1.4, -24, -0.3), (1.85, -28, 0.4)])
    extra = [(stereo(thump_fn(0.8, 80, 36, 0.05, 0.12, 2.5)), 0.002, -7.0)]
    return gunshot(shot, rng, dur=2.8, thump=(200, 60, 0.018, 0.055), thump_db=-6.0, spike_drive=6.0, thump_drive=2.5,
                   crack_db=-3.0, crack_tau=0.005, low_shelf=(90, 6.0), presence=(3000, 3.0),
                   tail_ir=ir, tail_db=1.0, tail_src_ms=100, natural=nat, natural_db=-11,
                   comp=(-26, 4.0, 1.0, 200), drive=2.0, extra=extra)


@sfx("dry_fire", 1, st=True, peak=-6.0, trim_db=-60)
def dry_fire(i, rng):
    # hammer/striker fall on empty chamber: crisp double metal click, tiny body, no report
    c1 = metal_clack(1, 1.6, 1200, 0.04)
    c2 = metal_clack(6, 1.9, 2000, 0.03)
    tick = modal(0.05, [3100, 4700, 6900], [1, 0.5, 0.3], [0.008, 0.005, 0.003], rng)
    body = thump(0.05, 700, 300, 0.005, 0.008, 0.0005)
    x = mix((c1, 0, 0), (tick, 0.0, -6), (body, 0, -12), (c2, 0.022, -5))
    return stereo(x, 1)


# =============================================================================== feedback
@sfx("hitmarker", 1, st=True, peak=-4.0, trim_db=-60, fout=0.006)
def hitmarker(i, rng):
    """Short, high, crisp 'tick' with a tiny body (~25 ms): hard click + band-limited noise snap
    + very short inharmonic 1.8-4 kHz ring (plastic/metal tick) + 600 Hz body."""
    n = secs(0.05)
    imp = click(0.09, 1500, 0.01)
    snap = burst(0.03, 1600, 6000, 0.0022, rng, 0.00003, order=2)
    ring = modal(0.05, [2300, 3150, 4250, 1850], [1.0, 0.7, 0.4, 0.35], [0.0065, 0.005, 0.0035, 0.006], rng, 0.0001)
    body = thump(0.02, 900, 560, 0.003, 0.0035, 0.0002)
    x = mix((imp, 0, -1), (snap, 0, -3), (ring, 0.0001, -4), (body, 0, -10),
            (snap * 0.6, 0.0028, -15), (ring * 0.4, 0.0028, -15), n=n)
    x = softclip(normalize(x, 0), 1.8)
    return stereo(x)


@sfx("hitmarker_kill", 1, st=True, peak=-3.0, trim_db=-60, fout=0.015)
def hitmarker_kill(i, rng):
    """Heavier kill-confirm: lower, thicker tick + punchy body thump + short second tick."""
    n = secs(0.16)
    imp = click(0.2, 700, 0.02)
    snap = burst(0.05, 1000, 7000, 0.005, rng, 0.00005)
    ring = modal(0.12, [1450, 2150, 3050, 4300], [1.0, 0.8, 0.5, 0.25], [0.018, 0.013, 0.009, 0.006], rng, 0.0002)
    body = thump(0.12, 340, 120, 0.01, 0.028, 0.0004, 2.2)
    tick2 = modal(0.04, [2600, 3900], [1, 0.5], [0.006, 0.004], rng)
    x = mix((imp, 0, 0), (snap, 0, -4), (ring, 0.0002, -4), (body, 0, -4), (tick2, 0.038, -11),
            (burst(0.03, 2000, 8000, 0.002, rng), 0.038, -14), n=n)
    x = softclip(normalize(x, 0), 2.0)
    return stereo(x)


@sfx("headshot", 1, st=True, peak=-3.0, trim_db=-66, fout=0.05)
def headshot(i, rng):
    """Helmet 'dink' (inharmonic metal ping) + bone/flesh crunch."""
    n = secs(0.6)
    ping = modal(0.6, [2150, 3380, 4960, 6890, 8420], [1.0, 0.6, 0.4, 0.2, 0.1],
                 [0.17, 0.11, 0.07, 0.04, 0.025], rng, 0.0002)
    ping = ping * (1 + 0.15 * np.sin(2 * np.pi * 9 * tvec(len(ping))))  # slight wobble of a helmet shell
    imp = click(0.15, 1500, 0.02)
    punch = S.kenney("impactPunch_medium_001.ogg")
    punch = hp(first_hit(punch), 250)[: secs(0.15)]
    crunch = grains(0.07, 700, rng, 900, 6000, 0.002, 0.02)
    x = mix((imp, 0, -4), (ping, 0, -2), (normalize(punch, 0), 0.0, -6), (normalize(crunch, 0), 0.002, -5), n=n)
    return stereo(x, 1)


# =============================================================================== enemy weapons
@sfx("enemy_fire", 4, st=False, peak=-1.0, trim_db=-60)
def enemy_fire(i, rng):
    """AK-47 (real) heard from ~30-60 m: mono, duller, less transient, more environment."""
    shot = take("AK-47", "C_28P.wav", i, 1.8, ratio=[1.0, 0.98, 1.02, 0.99][i])
    x = mono(shot)
    x = softclip(normalize(x, 0) * 4.0, 1.0)
    x = lp(hp(x, 70), 5200, 2)
    x = peq(x, 180, 3.0, 0.8)
    ir = make_ir(1.6, 1.4, 0.45, 1200, 0.0,
                 [(0.07, -12, 0), (0.13, -15, 0), (0.24, -19, 0), (0.4, -23, 0), (0.65, -28, 0)], 2500, 6, rng, st=False, lo_cut=60)
    tl = convolve(fade(x[: secs(0.08)], 0, 0.02), ir)
    tl = tl / (np.sqrt(np.mean(tl ** 2)) + 1e-12) * np.sqrt(np.mean(x[: secs(0.25)] ** 2))
    th = thump(0.4, 130, 60, 0.02, 0.04, 0.0015, 2.0)
    y = mix((normalize(x, 0), 0, 0), (tl, 0.0, -12.0), (th, 0.001, -10), n=secs(1.8))
    y = compress(normalize(y, 0), -18, 2.5, 2.0, 150, 6)
    return softclip(normalize(y, 0), 1.5)


# =============================================================================== foley
def seg(x, t0, t1, fin=0.002, fout=0.02):
    return fade(x[secs(t0):secs(t1)], fin, fout)


def foley_clean(x, hpf=90.0, air=2.0):
    x = mono(x)
    x = hp(x, hpf, 2)
    x = shelf(x, 6000, air, "high")
    return x


def cloth(dur, rng, lo=500, hi=6000, rate=18.0, intensity=1.0, shape=None):
    """Fabric rustle: band-passed noise with grainy random amplitude + friction crackle."""
    n = secs(dur)
    base = bp(pink(n, rng), lo, hi, 2)
    am = (0.25 + np.clip(smooth_rand(n, rate, rng) * 0.6 + 0.5, 0, None)) ** 2
    am2 = np.clip(smooth_rand(n, rate * 4, rng) * 0.4 + 0.7, 0, None)
    crack = grains(dur, 120 * intensity, rng, 2500, 9000, 0.0015, amp_sd=0.4)
    crack = crack / (np.abs(crack).max() + 1e-9) * np.abs(base).max() * 0.5
    if shape is None:
        shape = adsr(n, dur * 0.25, dur * 0.3, 0.5, dur * 0.4)
    x = base * am * am2 * shape + crack * shape * 0.25
    return x


@sfx("mag_out", 2, peak=-6.0, trim_db=-55)
def mag_out(i, rng):
    if i == 0:
        x = seg(S.oga("oga_ar_reload"), 0.10, 0.48)
    else:
        x = seg(S.oga("oga_gun_reload"), 0.03, 0.42)
    x = foley_clean(x, 120)
    x = mix((x, 0, 0), (cloth(0.3, rng, 400, 4000), 0.05, -22))
    return x


@sfx("mag_in", 2, peak=-4.0, trim_db=-55)
def mag_in(i, rng):
    if i == 0:
        x = seg(S.oga("oga_ar_reload"), 1.00, 1.21, fout=0.03)
    else:
        x = seg(S.oga("oga_handgun_reload"), 0.54, 0.86, fout=0.03)
    x = foley_clean(x, 100)
    lock = metal_clack(i + 2, 1.2, 1200, 0.05)
    th = thump(0.08, 220, 110, 0.01, 0.018, 0.0008)
    on = onsets(x, -10, 6, 0.05)
    t = on[-1] if on else 0.05
    return mix((x, 0, 0), (lock, t, -12), (th, t, -14))


@sfx("mag_tap", 1, peak=-4.0, trim_db=-55)
def mag_tap(i, rng):
    # palm slap seating the mag: fleshy thud + metal/plastic knock
    x = foley_clean(S.oga("oga_clipload2"), 100)
    slap = S.kenney("impactSoft_medium_002.ogg")
    slap = hp(first_hit(slap), 150)[: secs(0.12)]
    th = thump(0.1, 180, 90, 0.012, 0.02, 0.0008)
    on = onsets(x, -10, 6, 0.05)
    t = on[0] if on else 0.07
    return mix((x, 0, 0), (normalize(slap, 0), t - 0.002, -6), (th, t, -12))


@sfx("bolt_pull", 1, peak=-4.0, trim_db=-55)
def bolt_pull(i, rng):
    x = foley_clean(seg(S.oga("oga_gun_reload"), 0.62, 1.15, fout=0.04), 120)
    return mix((x, 0, 0), (metal_clack(3, 1.3, 1500, 0.04), 0.06, -16))


@sfx("bolt_release", 1, peak=-2.0, trim_db=-55)
def bolt_release(i, rng):
    x = foley_clean(seg(S.oga("oga_gun_reload"), 1.24, 1.58, fout=0.05), 90)
    on = onsets(x, -10, 6, 0.05)
    t = on[0] if on else 0.03
    th = thump(0.12, 260, 110, 0.012, 0.03, 0.0008, 1.8)
    return mix((x, 0, 0), (metal_clack(0, 1.0, 900, 0.07), t, -9), (th, t, -12))


@sfx("pistol_slide", 1, peak=-3.0, trim_db=-55)
def pistol_slide(i, rng):
    x = foley_clean(seg(S.oga("oga_handgun_reload"), 1.0, 1.45, fout=0.04), 110)
    on = onsets(x, -10, 6, 0.05)
    t = on[-1] if on else 0.15
    return mix((x, 0, 0), (metal_clack(4, 1.4, 1500, 0.05), t, -12))


@sfx("shotgun_shell", 3, peak=-5.0, trim_db=-55)
def shotgun_shell(i, rng):
    x = S.oga("oga_shotgun_reload", sub="4 Shell Reload.mp3")
    t0 = [1.12, 2.18, 3.24][i]
    y = foley_clean(seg(x, t0, t0 + 0.68, fout=0.05), 110)
    return y


@sfx("shotgun_pump", 1, peak=-2.0, trim_db=-55)
def shotgun_pump(i, rng):
    x = S.oga("oga_shotgun_reload", sub="Rack.mp3")
    y = foley_clean(seg(x, 0.60, 1.128, fout=0.05), 80)
    th1 = thump(0.1, 200, 100, 0.01, 0.025, 0.0008, 1.5)
    return mix((y, 0, 0), (th1, 0.036, -14), (th1, 0.219, -12))


@sfx("sniper_bolt", 1, peak=-3.0, trim_db=-55)
def sniper_bolt(i, rng):
    # bolt handle up (click) -> back (slide, from recording) -> forward -> down (lock)
    cock = foley_clean(S.oga("oga_shotgun_cock"), 120)
    cock = resample_ratio(cock, 1.12)
    up = metal_clack(2, 1.5, 1500, 0.04)
    down = metal_clack(5, 1.25, 1000, 0.06)
    slide = bp(noise(secs(0.12), rng), 1500, 7000) * adsr(secs(0.12), 0.02, 0.05, 0.4, 0.05)
    return mix((up, 0, -6), (slide, 0.04, -24), (cock, 0.08, 0), (down, 0.62, -5),
               (thump(0.08, 240, 120, 0.01, 0.02, 0.0008), 0.62, -14))


@sfx("weapon_raise", 2, peak=-8.0, trim_db=-55, fin=0.004)
def weapon_raise(i, rng):
    d = [0.42, 0.36][i]
    c = cloth(d, rng, 350, 5000, 14 + 4 * i)
    rattle = grains(d, 60, rng, 2500, 9000, 0.002, amp_sd=0.5) * adsr(secs(d), d * 0.3, d * 0.2, 0.5, d * 0.3)
    clack = metal_clack(i + 1, 1.15 + 0.1 * i, 1100, 0.05)
    return mix((c, 0, 0), (rattle, 0, -6), (clack, d - 0.07, -4))


@sfx("weapon_lower", 1, peak=-9.0, trim_db=-55, fin=0.004)
def weapon_lower(i, rng):
    d = 0.34
    c = cloth(d, rng, 300, 4500, 12, shape=adsr(secs(d), 0.04, 0.12, 0.5, 0.2))
    rattle = grains(d, 40, rng, 2500, 8000, 0.002, amp_sd=0.5) * expenv(secs(d), 0.12)
    return mix((metal_clack(6, 1.0, 900, 0.05), 0.0, -6), (c, 0.01, 0), (rattle, 0, -8))


@sfx("ads_in", 1, peak=-10.0, trim_db=-55, fin=0.004)
def ads_in(i, rng):
    d = 0.2
    c = cloth(d, rng, 600, 7000, 22, shape=adsr(secs(d), 0.06, 0.05, 0.6, 0.1))
    tick = metal_clack(7, 1.6, 2000, 0.03)
    return mix((c, 0, 0), (tick, 0.13, -6))


@sfx("ads_out", 1, peak=-11.0, trim_db=-55, fin=0.004)
def ads_out(i, rng):
    d = 0.17
    return cloth(d, rng, 500, 6000, 20, shape=adsr(secs(d), 0.03, 0.05, 0.5, 0.1))


@sfx("cloth", 3, peak=-9.0, trim_db=-55, fin=0.004)
def cloth_fx(i, rng):
    d = [0.35, 0.45, 0.28][i]
    return cloth(d, rng, 300 + 100 * i, 5000 + 800 * i, 14 + 5 * i, intensity=1.0 + 0.3 * i)


# =============================================================================== movement
def step_src(k):
    return S.kenney(f"footstep_concrete_{k:03d}.ogg")


def first_hit(x, pre=0.001):
    on = onsets(x, -24, 6, 0.1)
    s = secs(max(0.0, (on[0] if on else 0) - pre))
    return x[s:]


@sfx("footstep_concrete", 6, peak=-12.0, trim_db=-50, fout=0.03)
def footstep_concrete(i, rng):
    k = [0, 1, 2, 3, 4, 2][i]
    x = first_hit(step_src(k))
    if i == 5:
        x = resample_ratio(x, 0.93)
    x = hp(x, 70, 2)
    x = peq(x, 3500, 2.0, 0.8)          # grit / crispness
    heel = thump(0.07, 180, 90, 0.01, 0.015, 0.0008)
    grit = grains(0.08, 250, rng, 3000, 10000, 0.001, env_tau=0.03)
    return mix((normalize(x, 0), 0, 0), (heel, 0, -20), (grit, 0.004, -26))


@sfx("footstep_metal", 4, peak=-12.0, trim_db=-50, fout=0.04)
def footstep_metal(i, rng):
    x = first_hit(step_src(i))
    x = hp(x, 90, 2)
    plate = first_hit(S.kenney(f"impactPlate_light_{(i + 1) % 5:03d}.ogg"))
    plate = resample_ratio(plate, [0.8, 0.86, 0.75, 0.9][i])
    ring = modal(0.35, [310 + 20 * i, 735, 1220, 2350], [0.6, 1.0, 0.6, 0.3], [0.08, 0.06, 0.04, 0.025], rng)
    return mix((x, 0, -2), (normalize(plate, 0), 0.002, -6), (ring, 0.002, -16))


@sfx("jump", 1, peak=-10.0, trim_db=-50, fin=0.003)
def jump(i, rng):
    scuff = hp(first_hit(step_src(3)), 250)
    whoosh = cloth(0.3, rng, 300, 3000, 10, shape=adsr(secs(0.3), 0.05, 0.08, 0.4, 0.15))
    return mix((normalize(scuff, 0), 0, -4), (whoosh, 0.02, -2))


@sfx("land", 3, peak=-8.0, trim_db=-50)
def land(i, rng):
    a = first_hit(step_src([1, 3, 4][i]))
    b = first_hit(step_src([2, 0, 1][i]))
    th = thump(0.2, 140, 55, 0.02, 0.05, 0.001, 1.8)
    c = cloth(0.25, rng, 300, 4000, 20, shape=expenv(secs(0.25), 0.07, 0.005))
    grit = grains(0.15, 300, rng, 2500, 9000, 0.0012, env_tau=0.04)
    x = mix((a, 0, 0), (b, 0.018 + 0.006 * i, -3), (th, 0, -10), (c, 0.0, -8), (grit, 0.004, -18))
    return lp(x, 9000)


@sfx("slide", 1, peak=-6.0, trim_db=-50, fin=0.004, fout=0.12)
def slide(i, rng):
    """~0.9 s gritty scrape: body on concrete, gravel grit, cloth friction."""
    d = 0.9
    n = secs(d)
    env = adsr(n, 0.04, 0.2, 0.7, 0.3)
    base = bp(brown(n, rng), 120, 2200, 2) * (0.7 + 0.3 * smooth_rand(n, 25, rng))
    grit = grains(d, 900, rng, 1500, 8000, 0.0015, amp_sd=0.9)
    grit2 = grains(d, 250, rng, 600, 3500, 0.003, amp_sd=0.8)
    hiss = bp(noise(n, rng), 2500, 9000) * (0.6 + 0.4 * smooth_rand(n, 30, rng))
    c = cloth(d, rng, 400, 5000, 25)
    rumble = lp(noise(n, rng), 150, 2) * 2.0
    start = first_hit(step_src(0))
    x = (normalize(base, 1) * 0.9 + normalize(grit, 1) * 0.55 + normalize(grit2, 1) * 0.45
         + normalize(hiss, 1) * 0.12 + normalize(rumble, 1) * 0.3) * env
    x = mix((x, 0, 0), (c, 0, -12), (normalize(start, 0), 0, -4))
    return x


# =============================================================================== impacts
def kn(name):
    return first_hit(S.kenney(name))


@sfx("impact_concrete", 4, peak=-3.0, trim_db=-55)
def impact_concrete(i, rng):
    """Bullet into concrete: sharp crack + stone chip (pickaxe-on-rock recording) + debris patter."""
    rock = kn(f"impactMining_{i:03d}.ogg")
    rock = resample_ratio(hp(rock, 200), [1.25, 1.35, 1.2, 1.3][i])
    rock = fade(lp(rock, 6000, 2)[: secs(0.09)], 0, 0.06)
    crack = burst(0.03, 2500, 14000, 0.003, rng, 0.00005)
    snap = click(0.08, 2000, 0.01)
    debris = grains(0.35, 90, rng, 2000, 9000, 0.0025, env_tau=0.12)
    dust = bp(noise(secs(0.25), rng), 800, 5000) * expenv(secs(0.25), 0.05, 0.002)
    th = thump(0.06, 400, 150, 0.006, 0.012, 0.0005)
    return mix((snap, 0, -2), (crack, 0, -4), (normalize(rock, 0), 0.001, -4), (debris, 0.02, -16),
               (dust, 0.004, -20), (th, 0, -12))


@sfx("impact_metal", 4, peak=-3.0, trim_db=-55)
def impact_metal(i, rng):
    names = ["impactMetal_medium_000.ogg", "impactMetal_medium_002.ogg", "impactPlate_medium_001.ogg",
             "impactMetal_heavy_003.ogg"]
    m = resample_ratio(hp(kn(names[i]), 300), [1.3, 1.4, 1.2, 1.5][i])
    ping = modal(0.4, [1900 + 150 * i, 3100 + 200 * i, 4700, 6800], [1, 0.7, 0.5, 0.3],
                 [0.07, 0.05, 0.035, 0.02], rng)
    crack = burst(0.02, 3000, 15000, 0.0018, rng, 0.00003)
    return mix((click(0.06, 2500, 0.01), 0, -2), (crack, 0, -3), (normalize(m, 0), 0.0005, -3), (ping, 0.0005, -20))


@sfx("impact_dirt", 3, peak=-4.0, trim_db=-55)
def impact_dirt(i, rng):
    soft = kn(f"impactSoft_heavy_{i:03d}.ogg")
    soft = resample_ratio(hp(soft, 80), [1.1, 1.2, 1.05][i])
    th = thump(0.12, 180, 70, 0.012, 0.03, 0.0005, 1.5)
    puff = lp(noise(secs(0.2), rng), 1800) * expenv(secs(0.2), 0.04, 0.001)
    spray = grains(0.4, 70, rng, 700, 5000, 0.004, env_tau=0.15)
    return mix((normalize(soft, 0), 0, 0), (th, 0, -6), (puff, 0, -10), (spray, 0.03, -16),
               (burst(0.02, 1500, 6000, 0.002, rng), 0, -10))


@sfx("impact_flesh", 4, peak=-3.0, trim_db=-55)
def impact_flesh(i, rng):
    names = ["impactPunch_medium_000.ogg", "impactPunch_heavy_001.ogg", "impactPunch_medium_003.ogg",
             "impactPunch_heavy_004.ogg"]
    p = hp(kn(names[i]), 90)
    n = secs(0.18)
    wet = bp(noise(n, rng), 400, 1800) * expenv(n, 0.03, 0.002) * (0.6 + 0.4 * smooth_rand(n, 90, rng))
    wet = env_filter(wet, np.linspace(1400, 500, n // 256 + 1), "bp", 0.8)
    th = thump(0.1, 160, 70, 0.01, 0.025, 0.0006, 1.8)
    return mix((normalize(p, 0), 0, 0), (normalize(wet, 0), 0.004, -8), (th, 0, -6))


@sfx("impact_wood", 2, peak=-3.0, trim_db=-55)
def impact_wood(i, rng):
    w = hp(kn(["impactWood_medium_001.ogg", "impactWood_heavy_002.ogg"][i]), 120)
    w = resample_ratio(w, [1.2, 1.1][i])
    splint = grains(0.15, 200, rng, 1500, 7000, 0.002, env_tau=0.04)
    crack = burst(0.03, 1800, 9000, 0.004, rng, 0.0001)
    return mix((crack, 0, -3), (normalize(w, 0), 0.0005, 0), (splint, 0.003, -12))


@sfx("ricochet", 3, peak=-4.0, trim_db=-55, fout=0.06)
def ricochet(i, rng):
    """Metal spang + whining ricochet flyby (descending glide)."""
    d = [0.55, 0.7, 0.45][i]
    n = secs(d)
    f0, f1 = [(4200, 1500), (3500, 1100), (5200, 2300)][i]
    t = tvec(n)
    f = f1 + (f0 - f1) * np.exp(-t / (d * 0.5))
    f = f * (1 + 0.012 * np.sin(2 * np.pi * (35 + 10 * i) * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    whine = np.sin(ph) + 0.35 * np.sin(2 * ph + 0.3) + 0.12 * np.sin(3 * ph)
    whine *= adsr(n, 0.01, 0.1, 0.8, d * 0.6) * np.linspace(1, 0.4, n)
    air = env_filter(noise(n, rng), f * 1.0, "bp", 0.3)[:n] * adsr(n, 0.01, 0.1, 0.7, d * 0.6)
    hit = mix((click(0.05, 3000, 0.01), 0, 0), (burst(0.02, 3000, 15000, 0.002, rng), 0, -3),
              (modal(0.2, [2600, 4100, 6300], [1, 0.6, 0.4], [0.05, 0.03, 0.02], rng), 0, -8))
    whine *= np.exp(-tvec(n) / (d * 0.35))
    x = mix((hit, 0, 0), (whine, 0.008, -13), (normalize(air, 0), 0.008, -12))
    return x


# =============================================================================== threat
@sfx("bullet_whiz", 4, peak=-3.0, trim_db=-55, fout=0.05)
def bullet_whiz(i, rng):
    """Supersonic flyby: N-wave crack followed by a doppler 'fwip' of air."""
    d = [0.32, 0.28, 0.38, 0.3][i]
    n = secs(d)
    # N-wave: sharp rise, linear fall through zero, sharp return (~0.6 ms)
    w = secs(0.0006 + 0.0002 * i)
    nw = np.zeros(secs(0.01))
    nw[:w] = np.linspace(1, -1, w)
    nw = hp(lp(nw, 14000, 2), 600, 2)
    crack_tail = burst(0.05, 1500, 9000, 0.006, rng, 0.0)
    # whoosh: noise band-pass with centre sweeping down (doppler)
    fc = np.geomspace([3200, 2800, 3600, 3000][i], [700, 600, 900, 650][i], n // 256 + 1)
    wh = env_filter(noise(n, rng), fc, "bp", 0.9)
    pk = [0.05, 0.04, 0.07, 0.05][i]
    t = tvec(n)
    env = np.where(t < pk, (t / pk) ** 1.5, np.exp(-(t - pk) / (d * 0.25)))
    wh = wh * env
    ir = make_ir(0.3, 0.3, 0.12, 1500, 0, [(0.03, -12, 0)], 3000, 0, rng, st=False)
    x = mix((nw, 0, 0), (crack_tail, 0.0005, -14), (normalize(wh, 0), 0.0, -7))
    tl = convolve(x[: secs(0.02)], ir)
    return mix((x, 0, 0), (tl / (np.abs(tl).max() + 1e-9), 0, -20))


@sfx("player_hurt", 3, st=True, peak=-3.0, trim_db=-55)
def player_hurt(i, rng):
    """Taking a hit: body impact + low 'thud' + muffled ear-pressure whump (no voice)."""
    p = hp(kn(["impactPunch_heavy_000.ogg", "impactPunch_heavy_002.ogg", "impactPunch_heavy_003.ogg"][i]), 60)
    th = thump(0.3, 120, 45, 0.03, 0.07, 0.001, 2.0)
    whump = lp(noise(secs(0.35), rng), 400) * expenv(secs(0.35), 0.08, 0.005)
    grit = grains(0.08, 400, rng, 1500, 6000, 0.002, env_tau=0.02)
    x = mix((normalize(p, 0), 0, 0), (th, 0, -3), (normalize(whump, 0), 0, -10), (grit, 0.002, -14))
    return stereo(softclip(normalize(x, 0), 1.5), 1)


@sfx("heartbeat", 1, st=True, peak=-4.0, trim_db=-60, fout=0.08)
def heartbeat(i, rng):
    """'Lub-dub' — two low thumps ~0.3 s apart (one beat, re-triggered by the game)."""
    lub = thump(0.25, 75, 42, 0.03, 0.06, 0.004, 1.8)
    dub = thump(0.22, 90, 50, 0.025, 0.05, 0.003, 1.8)
    lubt = lp(noise(secs(0.08), rng), 300) * expenv(secs(0.08), 0.02, 0.003)
    x = mix((lub, 0, 0), (lubt, 0, -12), (dub, 0.29, -3), (lubt, 0.29, -15), n=secs(0.8))
    return stereo(lp(x, 500))


@sfx("death", 1, st=True, peak=-2.0, trim_db=-60, fout=0.4)
def death(i, rng):
    """Heavy hit -> tinnitus ring + muffled low rumble, fading out (~2.6 s)."""
    d = 2.6
    n = secs(d)
    hit = mix((thump(0.6, 110, 32, 0.05, 0.16, 0.001, 2.5), 0, 0),
              (normalize(hp(kn("impactPunch_heavy_004.ogg"), 60), 0), 0, -4),
              (lp(noise(secs(0.8), rng), 250) * expenv(secs(0.8), 0.25, 0.005), 0, -6))
    t = tvec(n)
    ring = (np.sin(2 * np.pi * 3520 * t) * 0.7 + np.sin(2 * np.pi * 3528 * t + 1) * 0.3)
    ring *= np.clip(t / 0.15, 0, 1) * np.exp(-t / 1.1)
    rumble = lp(brown(n, rng), 120) * np.exp(-t / 0.9)
    x = mix((hit, 0, 0), (ring, 0.05, -20), (normalize(rumble, 0), 0, -12), n=n)
    L = x
    R = mix((hit, 0, 0), (ring * 0.9, 0.05, -20), (normalize(rumble, 0), 0.0007, -12), n=n)
    return np.stack([L, R], 1)


# =============================================================================== explosives / misc
@sfx("explosion", 2, st=False, peak=-1.0, trim_db=-60, fout=0.3)
def explosion(i, rng):
    """Grenade: pitched-down real 12ga report as the blast front + sub boom + debris + long rumble."""
    d = 3.2
    n = secs(d)
    blast = take(["Mossberg", "Model 12"][i], ["N_30P.wav", "K_22P.wav"][i], 0, 3.0, ratio=[0.42, 0.38][i])
    blast = mono(blast)
    blast = softclip(normalize(blast, 0) * 6, 1.0)
    blast = fade(lp(blast, 5000)[: secs(0.45)], 0, 0.25)
    sub = thump(3.0, 70, 28, 0.12, 0.28, 0.002, 2.5)
    nb = noise(n, rng)
    roar = sweep_filter(nb, 3500, 180, "lp") * expenv(n, 0.45, 0.004)
    debris = grains(2.0, 70, rng, 1500, 8000, 0.004, env_tau=0.7) * 1.0
    crackle = grains(1.2, 300, rng, 2000, 10000, 0.0012, env_tau=0.3)
    ir = make_ir(2.8, 2.5, 0.7, 900, 0.0,
                 [(0.12, -10, 0), (0.25, -13, 0), (0.45, -17, 0), (0.8, -26, 0)], 1800, 6, rng, st=False, lo_cut=35)
    core = mix((normalize(blast, 0), 0, 0), (sub, 0, -2), (normalize(roar, 0), 0, -5), n=n)
    tl = convolve(core[: secs(0.25)], ir)
    tl = tl / (np.sqrt(np.mean(tl ** 2)) + 1e-12) * np.sqrt(np.mean(core[: secs(0.5)] ** 2))
    x = mix((core, 0, 0), (tl, 0, -2), (normalize(debris, 0), 0.15, -18), (normalize(crackle, 0), 0.02, -16), n=n)
    x = compress(normalize(x, 0), -20, 3.0, 3.0, 250, 6)
    return softclip(normalize(x, 0), 1.8)


def casing(rng, bounces, freqs, decays, dur, damp=1.0, lo=2500):
    """Brass casing: a few bounces, each exciting inharmonic ringing partials."""
    n = secs(dur)
    x = np.zeros(n)
    t = 0.0
    a = 1.0
    gap = rng.uniform(0.07, 0.11)
    for b in range(bounces):
        amps = rng.uniform(0.3, 1.0, len(freqs))
        f = np.array(freqs) * rng.uniform(0.995, 1.005)
        ring = modal(dur - t, f, amps, np.array(decays) * damp * (0.6 + 0.4 * a), rng, 0.00005)
        tick = click(0.05, lo, 0.01)
        s = secs(t)
        seg_ = ring[: n - s] * a
        x[s:s + len(seg_)] += seg_
        x[s:s + len(tick)] += tick[: n - s] * a * 1.5
        t += gap
        gap *= rng.uniform(0.55, 0.75)
        a *= rng.uniform(0.45, 0.65)
        if t >= dur - 0.02:
            break
    return hp(x, lo * 0.8, 2)


@sfx("shell_casing_concrete", 4, peak=-10.0, trim_db=-55, fout=0.05)
def shell_casing_concrete(i, rng):
    base = [4050, 5530, 7420, 9800]
    f = [b * [1.0, 1.08, 0.94, 1.15][i] for b in base]
    return casing(rng, 4 + i % 2, f, [0.05, 0.035, 0.022, 0.012], 0.45, lo=2800)


@sfx("shell_casing_metal", 2, peak=-10.0, trim_db=-55, fout=0.06)
def shell_casing_metal(i, rng):
    base = [2600, 4050, 5530, 7420, 9800]
    f = [b * [1.0, 1.1][i] for b in base]
    x = casing(rng, 4, f, [0.08, 0.1, 0.07, 0.045, 0.02], 0.6, lo=1800)
    plate = modal(0.4, [880, 1370, 2130], [1, 0.7, 0.5], [0.06, 0.05, 0.03], rng)
    return mix((x, 0, 0), (plate, 0, -18))


@sfx("grenade_pin", 1, peak=-6.0, trim_db=-55, fout=0.05)
def grenade_pin(i, rng):
    # pin pull (scrape + click) and spoon ping
    scrape = bp(noise(secs(0.1), rng), 2500, 9000) * adsr(secs(0.1), 0.02, 0.03, 0.5, 0.04)
    c1 = metal_clack(7, 1.8, 2500, 0.03)
    ping = modal(0.35, [3350, 5120, 7600], [1, 0.6, 0.3], [0.09, 0.06, 0.03], rng)
    spoon = metal_clack(2, 1.3, 1500, 0.05)
    return mix((scrape, 0, -10), (c1, 0.09, -2), (ping, 0.09, -12), (spoon, 0.28, -5),
               (modal(0.25, [2200, 3900], [1, 0.5], [0.05, 0.03], rng), 0.28, -14))


@sfx("grenade_bounce", 2, peak=-5.0, trim_db=-55)
def grenade_bounce(i, rng):
    m = hp(kn(["impactMetal_heavy_001.ogg", "impactMetal_heavy_004.ogg"][i]), 150)
    m = resample_ratio(m, [0.9, 0.85][i])
    thud = thump(0.08, 260, 120, 0.01, 0.02, 0.0005)
    dirt = grains(0.1, 200, rng, 800, 5000, 0.002, env_tau=0.03)
    return mix((normalize(m, 0), 0, 0), (thud, 0, -6), (dirt, 0, -16))


@sfx("pickup_ammo", 1, st=True, peak=-6.0, trim_db=-55)
def pickup_ammo(i, rng):
    x = foley_clean(S.oga("oga_clipload1"), 120)
    rattle = grains(0.25, 90, rng, 2500, 9000, 0.003, env_tau=0.1)
    c = cloth(0.25, rng, 400, 5000, 20)
    ping = modal(0.2, [2600, 4100], [1, 0.5], [0.05, 0.03], rng)
    return stereo(mix((c, 0, -6), (x, 0.03, 0), (rattle, 0.05, -12), (ping, 0.12, -18)), 1)


# =============================================================================== UI
def ui_proc(x, hpf=150):
    x = hp(mono(x), hpf, 2)
    return stereo(x, 1)


@sfx("ui_hover", 1, st=True, peak=-12.0, trim_db=-55, fout=0.02)
def ui_hover(i, rng):
    x = kn("select_002.ogg")
    tick = modal(0.05, [2900, 4400], [1, 0.4], [0.01, 0.006], rng)
    return ui_proc(mix((x, 0, 0), (tick, 0, -14)), 300)


@sfx("ui_click", 1, st=True, peak=-10.0, trim_db=-55, fout=0.02)
def ui_click(i, rng):
    x = kn("click_002.ogg")
    th = thump(0.06, 420, 180, 0.006, 0.012, 0.0004)
    return ui_proc(mix((normalize(x, 0), 0, 0), (th, 0, -20)))


@sfx("ui_back", 1, st=True, peak=-10.0, trim_db=-55, fout=0.02)
def ui_back(i, rng):
    return ui_proc(kn("back_002.ogg"))


@sfx("countdown_tick", 1, st=True, peak=-8.0, trim_db=-60, fout=0.02)
def countdown_tick(i, rng):
    tone = modal(0.2, [1320, 2640, 3960], [1, 0.3, 0.12], [0.05, 0.03, 0.02], rng, 0.0008)
    x = mix((click(0.1, 1500, 0.01), 0, -6), (tone, 0, 0), (thump(0.05, 500, 250, 0.005, 0.01, 0.0005), 0, -12))
    return stereo(x, 1)


def saw(n, f, rng, detune=0.0, over=2):
    """Band-limited-ish saw (2x oversampled naive saw, decimated)."""
    m = n * over
    t = np.arange(m) / (SR * over)
    ph = (f * (1 + detune) * t + rng.uniform()) % 1.0
    y = 2 * ph - 1
    return signal.resample_poly(y, 1, over)[:n]


def note_hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def pad_voice(dur, midis, rng, cutoff=1500, detune=0.006, att=0.3, rel=0.6, voices=3):
    n = secs(dur)
    x = np.zeros((n, 2))
    for m in midis:
        for v in range(voices):
            dt = (v - (voices - 1) / 2) * detune
            y = saw(n, note_hz(m), rng, dt)
            p = (v / max(1, voices - 1)) * 2 - 1
            x += pan(y, p * 0.6)
    x = lp(x, cutoff, 2)
    env = adsr(n, att, dur * 0.4, 0.8, rel)
    return x * env[:, None]


def riser(dur, rng, f0=400, f1=6000):
    n = secs(dur)
    fc = np.geomspace(f0, f1, n // 256 + 1)
    x = np.stack([env_filter(noise(n, rng), fc, "bp", 0.6), env_filter(noise(n, rng), fc, "bp", 0.6)], 1)
    t = tvec(n) / dur
    return x * (t ** 2.2)[:, None]


@sfx("wave_start", 1, st=True, peak=-3.0, trim_db=-60, fout=0.3)
def wave_start(i, rng):
    """~2.3 s stinger: big low hit + dissonant brass 'braam', rising noise/tone riser into a final accent."""
    d = 2.4
    hit = mix((stereo(thump(1.2, 90, 32, 0.08, 0.35, 0.002, 2.5)), 0, 0),
              (stereo(normalize(take("Mossberg", "N_30P.wav", 0, 2.0, ratio=0.3).mean(1), 0)), 0, -8))
    hit = lp(hit, 3000)
    braam = pad_voice(1.8, [26, 33, 38, 39], rng, 900, 0.008, 0.02, 0.8)
    braam = softclip(normalize(braam, 0) * 2.0, 1.0)
    rs = riser(1.7, rng, 300, 7000)
    t = tvec(secs(1.7))
    tone = np.sin(2 * np.pi * np.cumsum(np.geomspace(110, 440, len(t))) / SR) * (t / 1.7) ** 2
    ir = make_ir(2.5, 2.2, 1.0, 1000, 0.0, [], 3000, 0, rng)
    acc = mix((stereo(thump(0.5, 140, 50, 0.03, 0.12, 0.001, 2.0)), 0, 0),
              (stereo(burst(0.2, 1500, 9000, 0.04, rng)), 0, -10))
    dry = mix((hit, 0, 0), (braam, 0.0, -6), (normalize(rs, 0), 0.55, -12), (stereo(tone), 0.55, -18),
              (acc, 2.25, -2), n=secs(d + 0.6))
    wet = convolve(dry, ir)[: len(dry)]
    x = mix((dry, 0, 0), (normalize(wet, 0), 0, -12))
    return softclip(normalize(x, 0), 1.4)


@sfx("wave_complete", 1, st=True, peak=-4.0, trim_db=-60, fout=0.5)
def wave_complete(i, rng):
    """Positive resolve: suspended -> major chord brass swell with a soft low hit and shimmer."""
    d = 2.6
    sus = pad_voice(0.7, [50, 55, 57, 62], rng, 2200, 0.005, 0.05, 0.3)
    maj = pad_voice(2.0, [50, 54, 57, 62, 66], rng, 2600, 0.005, 0.04, 1.2)
    hit = stereo(thump(0.6, 110, 45, 0.04, 0.15, 0.002, 2.0))
    shimmer = np.zeros((secs(1.6), 2))
    for k, m in enumerate([74, 78, 81, 86]):
        tone = modal(1.2, [note_hz(m)], [1], [0.5], rng, 0.002)
        shimmer = mix((shimmer, 0, 0), (pan(tone, -0.5 + k * 0.33), 0.06 * k, -6), n=len(shimmer))
    ir = make_ir(2.5, 2.2, 1.2, 1000, 0.0, [], 3000, 0, rng)
    dry = mix((sus, 0, -3), (maj, 0.55, 0), (hit, 0.55, -4), (shimmer, 0.6, -12), n=secs(d))
    wet = convolve(dry, ir)[: len(dry)]
    return mix((dry, 0, 0), (normalize(wet, 0), 0, -10))


@sfx("killstreak", 1, st=True, peak=-3.0, trim_db=-60, fout=0.4)
def killstreak(i, rng):
    """Reward stinger: punchy hit + fast rising brass triad + metallic shimmer."""
    hit = mix((stereo(thump(0.5, 160, 50, 0.03, 0.1, 0.001, 2.2)), 0, 0),
              (stereo(burst(0.15, 2000, 10000, 0.03, rng)), 0, -12))
    notes = [(57, 0.0), (61, 0.08), (64, 0.16), (69, 0.24)]
    x = [(hit, 0, 0)]
    for m, t in notes:
        x.append((pad_voice(0.9 - t, [m, m - 12], rng, 3000, 0.004, 0.01, 0.4), t, -6))
    ping = modal(1.0, [note_hz(81), note_hz(88)], [1, 0.5], [0.3, 0.2], rng)
    x.append((stereo(ping, 1), 0.24, -14))
    dry = mix(*x, n=secs(1.5))
    ir = make_ir(2.0, 1.8, 0.9, 1000, 0.0, [], 3000, 0, rng)
    wet = convolve(dry, ir)[: len(dry)]
    return softclip(normalize(mix((dry, 0, 0), (normalize(wet, 0), 0, -12)), 0), 1.3)


# =============================================================================== ambience (seamless loops)
def gull(rng, dur=0.45):
    n = secs(dur)
    t = tvec(n) / dur
    f0 = rng.uniform(1300, 1700)
    f = f0 * (1 + 0.45 * np.sin(np.pi * t) ** 0.7 - 0.25 * t) * (1 + 0.02 * np.sin(2 * np.pi * 28 * tvec(n)))
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = sum((0.6 ** k) * np.sin((k + 1) * ph) for k in range(6))
    rasp = 1 + 0.5 * bp(noise(n, rng), 60, 300) / 3
    y *= rasp * np.sin(np.pi * t) ** 0.8
    return bp(y, 900, 5000)


def creak(rng, dur=1.0):
    """Stick-slip creak: impulse train with wandering rate through metal resonances."""
    n = secs(dur)
    rate = 40 + 60 * (0.5 + 0.5 * smooth_rand(n, 3, rng))
    ph = np.cumsum(rate) / SR
    imp = np.diff(np.floor(ph), prepend=0) * rng.uniform(0.5, 1.0, n)
    y = sum(reson(imp, f, 30) * a for f, a in [(380, 1), (910, 0.7), (1650, 0.5), (2600, 0.3)])
    return y * adsr(n, 0.15, 0.3, 0.8, 0.3)


@sfx("amb_wind", 1, st=True, peak=-6.0, fmt="ogg", trim_db=None, fout=0.0)
def amb_wind(i, rng):
    """Harbour wind bed (18 s loop): gusting wind + whistle, water lapping, distant gulls & metal creaks."""
    L, XF = 18.0, 2.0
    n = secs(L + XF)
    t = tvec(n)
    gust = 0.55 + 0.45 * smooth_rand(n, 0.25, rng)
    wind = bp(pink(n, rng, True), 120, 2500, 2) * gust[:, None]
    fc = 500 + 400 * smooth_rand(n, 0.3, rng)
    whistle = np.stack([env_filter(noise(n, rng), fc * 1.6, "bp", 0.12),
                        env_filter(noise(n, rng), fc * 1.62, "bp", 0.12)], 1) * np.clip(gust - 0.5, 0, None)[:, None] ** 1.5
    rumble = lp(brown(n, rng, True), 90) * 0.8
    x = normalize(wind, 0) + normalize(whistle, 0) * 0.18 + normalize(rumble, 0) * 0.35
    # water lapping against the quay
    for tt in np.arange(0.3, L + XF - 1.5, 1.7) + rng.uniform(-0.3, 0.3, len(np.arange(0.3, L + XF - 1.5, 1.7))):
        dd = rng.uniform(0.8, 1.4)
        m = secs(dd)
        e = np.sin(np.pi * np.linspace(0, 1, m)) ** 2 * expenv(m, dd * 0.5)
        lap = bp(noise(m, rng), 150, 900) * e + bp(noise(m, rng), 900, 3000) * e ** 3 * 0.4
        addat(x, pan(lap, rng.uniform(-0.4, 0.4)), max(0, tt), -12 + rng.uniform(-3, 2))
    # distant gulls
    for tt in [1.5, 1.95, 7.3, 12.1, 12.5, 12.95, 16.4]:
        g = gull(rng, rng.uniform(0.35, 0.55))
        g = lp(g, 3500)
        addat(x, pan(g, rng.uniform(-0.8, 0.8)), tt, -20 + rng.uniform(-4, 0))
    # metal creaks (moored ships / cranes)
    for tt in [4.2, 10.0, 15.1]:
        c = lp(creak(rng, rng.uniform(0.8, 1.4)), 2500)
        addat(x, pan(c, rng.uniform(-0.7, 0.7)), tt, -22)
    ir = make_ir(2.5, 2.0, 0.8, 1000, 0.02, [], 3000, 0, rng)
    wet = convolve(x, ir)[:n]
    x = x + normalize(wet, 0) * 0.2 * np.abs(x).max()
    x = hp(x, 25, 2)
    return loopify(x, secs(L), XF)


def distant(x, lpf=1800.0):
    return lp(hp(mono(x), 150), lpf, 2)


@sfx("amb_battle", 1, st=True, peak=-4.0, fmt="ogg", trim_db=None, fout=0.0)
def amb_battle(i, rng):
    """Distant battle bed (18 s loop): sporadic far-off rifle fire, bursts and explosions."""
    L, XF = 18.0, 3.0
    n = secs(L + XF)
    x = lp(brown(n, rng, True), 120) * 0.25
    ir = make_ir(3.0, 2.8, 0.9, 700, 0.03,
                 [(0.18, -6, -0.5), (0.35, -9, 0.6), (0.6, -12, -0.3), (1.0, -16, 0.4)], 1500, 0, rng)
    events = []
    # far rifle bursts (real mid-distance AK / SMG / PPSh bursts)
    burst_src = [("AK-47", "C_36P.wav", 0), ("AK-47", "C_34P.wav", 0), ("Carl Gustav M45", "G_22P.wav", 0),
                 ("PPSh", "P_16P.wav", 0), ("AK-47", "C_31P.wav", 0), ("SKS", "U_19P.wav", 0)]
    t = 0.4
    k = 0
    while t < L + XF - 2.5:
        f, fn, _ = burst_src[k % len(burst_src)]
        src, on = shots_of(f, fn, 1.5)
        o = on[int(rng.integers(len(on)))]
        seg_ = slice_at(src, o, 0.01, rng.uniform(0.6, 1.4))
        seg_ = fade(seg_, 0.003, 0.25)
        events.append((pan(distant(seg_, rng.uniform(1200, 2500)), rng.uniform(-0.9, 0.9)), t,
                       rng.uniform(-22, -12)))
        t += rng.uniform(0.7, 2.2)
        k += 1
    # distant explosions
    for tt in [3.1, 11.4, 16.8]:
        blast = take("Mossberg", "N_30P.wav", 0, 3.0, ratio=rng.uniform(0.3, 0.4)).mean(1)
        blast = lp(softclip(normalize(blast, 0) * 5, 1), 700)
        b = mix((blast, 0, 0), (thump(1.5, 60, 28, 0.1, 0.4, 0.01, 2), 0, -3))
        events.append((pan(b, rng.uniform(-0.7, 0.7)), tt, -8))
    dry = mix((x, 0, 0), *events, n=n)
    wet = convolve(dry, ir)[:n]
    y = dry * 0.6 + wet / (np.abs(wet).max() + 1e-9) * np.abs(dry).max() * 0.8
    y = compress(normalize(hp(y, 25, 2), 0), -18, 2.5, 5, 300, 6)
    return loopify(y, secs(L), XF)


# =============================================================================== music
@sfx("music_menu", 1, st=True, peak=-3.0, fmt="ogg", trim_db=None, fout=0.0)
def music_menu(i, rng):
    """Tense atmospheric military drone/pulse. 96 BPM, 20 bars = 50 s seamless loop, D minor."""
    bpm = 96
    beat = 60.0 / bpm
    bars = 20
    L = bars * 4 * beat
    XF = 3.0
    n = secs(L + XF)
    t = tvec(n)
    out = []
    # --- drone: D1 + A1 + D2 detuned saws, slow filter breathing
    drone = np.zeros((n, 2))
    for m, g in [(26, 1.0), (33, 0.55), (38, 0.5)]:
        for v, dt in enumerate([-0.004, 0.0, 0.0045]):
            drone += pan(saw(n, note_hz(m), rng, dt), (v - 1) * 0.7) * g
    cut = 260 + 180 * (0.5 + 0.5 * np.sin(2 * np.pi * t / (L / 2)))
    drone = np.stack([env_filter(drone[:, c], cut[::256], "lp") for c in range(2)], 1)
    out.append((normalize(drone, 0), 0, -9))
    # --- pulse: 8th-note staccato bass (D2), accents, filter envelope; enters bar 3
    pulse = np.zeros((n, 2))
    pat = [1, 0.5, 0.7, 0.5, 1, 0.5, 0.8, 0.6]
    step = beat / 2
    notes_by_bar = [38, 38, 38, 38, 41, 41, 36, 37]  # D D D D F F C C# (tension)
    for b in range(2, bars):
        root = notes_by_bar[b % 8]
        for s_ in range(8):
            tt = b * 4 * beat + s_ * step
            m = secs(step * 0.9)
            y = saw(m, note_hz(root), rng) + saw(m, note_hz(root - 12), rng) * 0.6
            y = sweep_filter(y, 1400 * pat[s_], 180, "lp", 128) * expenv(m, 0.09, 0.003)
            addat(pulse, stereo(y), tt, 20 * np.log10(pat[s_]))
    swell = np.clip((t - 2 * 4 * beat) / (4 * beat), 0, 1)
    out.append((normalize(pulse, 0) * swell[:, None], 0, -8))
    # --- percussion: low taiko-ish hits (bar 5+), ticking 16th hats (bar 9+), snare roll into loop
    perc = np.zeros((n, 2))
    for b in range(4, bars):
        for pos, g in [(0, 0), (2.5, -4), (3.0, -6)] if b % 2 == 0 else [(0, -2), (1.5, -6), (3.5, -8)]:
            tt = (b * 4 + pos) * beat
            k = mix((thump(0.6, 120, 48, 0.03, 0.14, 0.002, 2.0), 0, 0),
                    (lp(noise(secs(0.2), rng), 900) * expenv(secs(0.2), 0.04, 0.001), 0, -10))
            addat(perc, pan(k, rng.uniform(-0.15, 0.15)), tt, g)
    for b in range(8, bars):
        for s16 in range(16):
            tt = (b * 4 + s16 / 4) * beat
            acc = 0 if s16 % 4 == 2 else -7
            h = bp(noise(secs(0.04), rng), 6000, 14000) * expenv(secs(0.04), 0.008, 0.0005)
            addat(perc, pan(h, 0.35), tt, -14 + acc)
    for b in (7, 15, 19):   # snare rolls into the next section (and into the loop start)
        for k in range(8):
            tt = (b * 4 + 3 + k / 8) * beat
            sn = bp(noise(secs(0.12), rng), 1200, 8000) * expenv(secs(0.12), 0.03, 0.001)
            sn = sn + thump(0.12, 240, 180, 0.01, 0.03, 0.001) * 0.4
            addat(perc, stereo(sn), tt, -16 + k * 1.2)
    out.append((normalize(perc, 0), 0, -4))
    # --- braams every 4 bars from bar 8
    for b in range(8, bars, 4):
        br = pad_voice(4 * beat * 1.6, [26, 38, 45, 50, 51], rng, 700, 0.007, 0.25, 1.5)
        br = softclip(normalize(br, 0) * 2.5, 1.0)
        out.append((br, b * 4 * beat, -10))
    # --- high tension strings: minor-second trill figure, bars 12-19
    for b in range(12, bars, 2):
        m1, m2 = (74, 75) if (b // 2) % 2 == 0 else (74, 77)
        dur = 8 * beat
        s1 = pad_voice(dur, [m1], rng, 5000, 0.003, 1.2, 1.5, 4)
        s2 = pad_voice(dur, [m2], rng, 5000, 0.003, 1.2, 1.5, 4)
        trem = (0.6 + 0.4 * np.sin(2 * np.pi * 6 * tvec(secs(dur))))[:, None]
        out.append(((s1 * 0.6 + s2 * 0.4) * trem, b * 4 * beat, -24))
    # --- reverse swell into bar 1 of the next loop (ends at L)
    rs = riser(2 * beat * 2, rng, 200, 4000)
    out.append((rs, L - 4 * beat, -26))
    # downbeat that lands the loop restart: placed at L so it sits in the part crossfaded into the start
    dn = mix((stereo(thump(1.2, 110, 38, 0.05, 0.3, 0.002, 2.5)), 0, 0),
             (softclip(normalize(pad_voice(3.0, [26, 38, 45], rng, 800, 0.007, 0.01, 2.0), 0) * 2, 1), 0, -6))
    out.append((dn, L, -4))
    dry = mix(*out, n=n)
    ir = make_ir(3.0, 2.6, 1.2, 900, 0.02, [(0.07, -12, -0.4), (0.13, -14, 0.5)], 3500, 0, rng)
    wet = convolve(dry, ir)[:n]
    y = dry + wet / (np.abs(wet).max() + 1e-9) * np.abs(dry).max() * 0.35
    y = compress(normalize(hp(y, 25, 2), 0), -16, 2.5, 8, 250, 6)
    y = softclip(normalize(y, 0), 1.2)
    return loopify(y, secs(L), XF)


# =============================================================================== main
def main(argv):
    only = set(argv)
    os.makedirs(OUT, exist_ok=True)
    t0 = time.time()
    total = 0
    for base, cnt, fn, o in REG:
        if only and base not in only:
            continue
        for i in range(cnt):
            name = f"{base}_{i + 1}"
            rng = rng_for(name)
            x = fn(i, rng)
            x = finalize(x, o)
            path = os.path.join(OUT, f"{name}.{o['fmt']}")
            write(path, x, o["fmt"])
            imp = path + ".import"
            if o["loop"] and os.path.exists(imp):   # keep Godot loop flags on regenerated loops
                txt = open(imp).read()
                txt = txt.replace("loop=false", "loop=true").replace("edit/loop_mode=0", "edit/loop_mode=2")
                open(imp, "w").write(txt)
            sz = os.path.getsize(path)
            total += sz
            print(f"{name:26s} {len(x)/SR:6.2f}s ch{x.shape[1] if x.ndim == 2 else 1} "
                  f"pk{peak_db(x):6.1f}  {sz/1024:7.1f} KB")
    print(f"done in {time.time()-t0:.1f}s, {total/1e6:.2f} MB written")


if __name__ == "__main__":
    main(sys.argv[1:])
