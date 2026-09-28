"""Small DSP toolkit used by gen_sfx.py (numpy/scipy only).

Conventions: audio arrays are float64, mono = 1-D (n,), stereo = 2-D (n, 2). SR = 44100.
"""
from fractions import Fraction
import numpy as np
from scipy import signal

SR = 44100


# ----------------------------------------------------------------------------- basics
def secs(n):
    return int(round(n * SR))


def tvec(n):
    return np.arange(n) / SR


def is_st(x):
    return x.ndim == 2


def mono(x):
    return x.mean(1) if x.ndim == 2 else x


def stereo(x, width=0.0, rng=None):
    """Mono -> stereo. width>0 adds a tiny decorrelated delay on one side (Haas-free, ~0.3 ms)."""
    if x.ndim == 2:
        return x
    if width <= 0:
        return np.stack([x, x], 1)
    d = max(1, int(width * 0.0003 * SR))
    r = np.concatenate([np.zeros(d), x[:-d]])
    return np.stack([x, r], 1)


def pad(x, n):
    if len(x) >= n:
        return x[:n]
    shp = (n - len(x),) + x.shape[1:]
    return np.concatenate([x, np.zeros(shp)])


def match(a, b):
    """Make channel layout of a match b."""
    if b.ndim == 2 and a.ndim == 1:
        return stereo(a)
    if b.ndim == 1 and a.ndim == 2:
        return mono(a)
    return a


def mix(*items, n=None):
    """mix((x, t_sec, gain_db), ...) -> buffer. Stereo if any item is stereo."""
    st = any(it[0].ndim == 2 for it in items)
    end = max(secs(it[1]) + len(it[0]) for it in items)
    n = n or end
    out = np.zeros((n, 2)) if st else np.zeros(n)
    for it in items:
        x, t = it[0], it[1]
        g = db2a(it[2]) if len(it) > 2 else 1.0
        if st:
            x = stereo(x)
        s = secs(t)
        if s >= n:
            continue
        seg = x[: n - s]
        out[s : s + len(seg)] += seg * g
    return out


def addat(buf, x, t, db=0.0):
    """In-place add x into buf at time t (s) with gain (dB); truncates at the end."""
    s = secs(t)
    if s >= len(buf):
        return buf
    if buf.ndim == 2:
        x = stereo(x)
    seg = x[: len(buf) - s]
    buf[s:s + len(seg)] += seg * db2a(db)
    return buf


def db2a(db):
    return 10.0 ** (db / 20.0)


def peak_db(x):
    return 20 * np.log10(np.abs(x).max() + 1e-12)


def normalize(x, peak=-1.0):
    m = np.abs(x).max()
    return x if m < 1e-12 else x * (db2a(peak) / m)


def gain(x, db):
    return x * db2a(db)


# ----------------------------------------------------------------------------- filters
def _sos(kind, f, order=2):
    nyq = SR / 2
    if kind == "bp":
        lo, hi = f
        lo = max(lo, 5.0)
        hi = min(hi, nyq * 0.98)
        return signal.butter(order, [lo / nyq, hi / nyq], "bandpass", output="sos")
    f = min(max(f, 5.0), nyq * 0.98)
    return signal.butter(order, f / nyq, {"lp": "lowpass", "hp": "highpass"}[kind], output="sos")


def lp(x, f, order=2):
    return signal.sosfilt(_sos("lp", f, order), x, axis=0)


def hp(x, f, order=2):
    return signal.sosfilt(_sos("hp", f, order), x, axis=0)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("bp", (lo, hi), order), x, axis=0)


def _biquad(b, a, x):
    return signal.lfilter(b, a, x, axis=0)


def peq(x, f, db, q=1.0):
    """RBJ peaking EQ."""
    A = 10 ** (db / 40)
    w = 2 * np.pi * f / SR
    al = np.sin(w) / (2 * q)
    b = np.array([1 + al * A, -2 * np.cos(w), 1 - al * A])
    a = np.array([1 + al / A, -2 * np.cos(w), 1 - al / A])
    return _biquad(b / a[0], a / a[0], x)


def shelf(x, f, db, kind="low", s=1.0):
    """RBJ shelving EQ."""
    A = 10 ** (db / 40)
    w = 2 * np.pi * f / SR
    al = np.sin(w) / 2 * np.sqrt((A + 1 / A) * (1 / s - 1) + 2)
    c = np.cos(w)
    if kind == "low":
        b = [A * ((A + 1) - (A - 1) * c + 2 * np.sqrt(A) * al), 2 * A * ((A - 1) - (A + 1) * c),
             A * ((A + 1) - (A - 1) * c - 2 * np.sqrt(A) * al)]
        a = [(A + 1) + (A - 1) * c + 2 * np.sqrt(A) * al, -2 * ((A - 1) + (A + 1) * c),
             (A + 1) + (A - 1) * c - 2 * np.sqrt(A) * al]
    else:
        b = [A * ((A + 1) + (A - 1) * c + 2 * np.sqrt(A) * al), -2 * A * ((A - 1) + (A + 1) * c),
             A * ((A + 1) + (A - 1) * c - 2 * np.sqrt(A) * al)]
        a = [(A + 1) - (A - 1) * c + 2 * np.sqrt(A) * al, 2 * ((A - 1) - (A + 1) * c),
             (A + 1) - (A - 1) * c - 2 * np.sqrt(A) * al]
    b, a = np.array(b), np.array(a)
    return _biquad(b / a[0], a / a[0], x)


def reson(x, f, q=20.0):
    """Two-pole resonator (band-pass, unity peak)."""
    b, a = signal.iirpeak(min(f, SR * 0.49) / (SR / 2), q)
    return _biquad(b, a, x)


def dcblock(x, f=18.0):
    return hp(x, f, 2)


def sweep_filter(x, f0, f1, kind="lp", block=256, curve="exp"):
    """Time-varying 2nd-order SVF-ish filter by blockwise coefficient update (state preserved)."""
    n = len(x)
    out = np.zeros_like(x)
    zi = None
    nb = (n + block - 1) // block
    for i in range(nb):
        u = i / max(1, nb - 1)
        f = f0 * (f1 / f0) ** u if curve == "exp" else f0 + (f1 - f0) * u
        sos = _sos(kind, f, 2)
        seg = x[i * block:(i + 1) * block]
        if zi is None:
            zi = np.zeros((sos.shape[0], 2) + seg.shape[1:])
        y, zi = signal.sosfilt(sos, seg, axis=0, zi=zi)
        out[i * block:(i + 1) * block] = y
    return out


def env_filter(x, freqs, kind="bp", bw=0.5, block=256):
    """Band-pass with per-block centre frequency given by array freqs (len >= nblocks)."""
    n = len(x)
    out = np.zeros_like(x)
    zi = None
    nb = (n + block - 1) // block
    for i in range(nb):
        fc = float(freqs[min(i, len(freqs) - 1)])
        if kind == "bp":
            sos = _sos("bp", (fc * (1 - bw / 2), fc * (1 + bw / 2)), 1)
        else:
            sos = _sos(kind, fc, 2)
        seg = x[i * block:(i + 1) * block]
        if zi is None:
            zi = np.zeros((sos.shape[0], 2) + seg.shape[1:])
        y, zi = signal.sosfilt(sos, seg, axis=0, zi=zi)
        out[i * block:(i + 1) * block] = y
    return out


# ----------------------------------------------------------------------------- generators
def noise(n, rng, st=False):
    return rng.standard_normal((n, 2) if st else n)


def pink(n, rng, st=False):
    """1/f noise via FFT shaping (periodic over n)."""
    def one():
        X = np.fft.rfft(rng.standard_normal(n))
        f = np.arange(len(X)); f[0] = 1
        X[: max(1, int(15.0 * n / SR))] = 0   # no sub-audio drift / DC
        y = np.fft.irfft(X / np.sqrt(f), n)
        return y / (np.std(y) + 1e-12)
    return np.stack([one(), one()], 1) if st else one()


def brown(n, rng, st=False):
    def one():
        X = np.fft.rfft(rng.standard_normal(n))
        f = np.arange(len(X)); f[0] = 1
        X[: max(1, int(15.0 * n / SR))] = 0   # no sub-audio drift / DC
        y = np.fft.irfft(X / f, n)
        return y / (np.std(y) + 1e-12)
    return np.stack([one(), one()], 1) if st else one()


def expenv(n, tau, att=0.0):
    t = tvec(n)
    e = np.exp(-t / max(tau, 1e-6))
    if att > 0:
        e *= np.clip(t / att, 0, 1)
    return e


def adsr(n, a, d, s, r, hold=None):
    t = tvec(n)
    dur = n / SR
    hold = dur - r if hold is None else hold
    e = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    rel = np.clip((t - hold) / max(r, 1e-6), 0, 1)
    return e * (1 - rel) ** 2


def sweep(n, f0, f1, tau, phase=0.0):
    """Sine whose frequency glides exponentially from f0 toward f1 with time-constant tau."""
    t = tvec(n)
    f = f1 + (f0 - f1) * np.exp(-t / tau)
    return np.sin(phase + 2 * np.pi * np.cumsum(f) / SR)


def thump(dur, f0, f1, tau_f, tau_a, att=0.0015, drive=1.0):
    n = secs(dur)
    x = sweep(n, f0, f1, tau_f) * expenv(n, tau_a, att)
    if drive > 1:
        x = np.tanh(drive * x) / np.tanh(drive)
    return x


def modal(dur, freqs, amps, decays, rng=None, att=0.0003):
    n = secs(dur)
    t = tvec(n)
    x = np.zeros(n)
    for f, a, d in zip(freqs, amps, decays):
        ph = rng.uniform(0, 2 * np.pi) if rng is not None else 0.0
        x += a * np.sin(2 * np.pi * f * t + ph) * np.exp(-t / d)
    if att > 0:
        x *= np.clip(t / att, 0, 1)
    return x


def burst(dur, lo, hi, tau, rng, att=0.0002, st=False, order=2):
    n = secs(dur)
    e = expenv(n, tau, att)
    x = bp(noise(n, rng, st), lo, hi, order)
    return x * (e[:, None] if st else e)


def click(width_ms=0.3, hpf=800.0, dur=0.01):
    n = secs(dur)
    w = max(2, int(width_ms * 1e-3 * SR))
    x = np.zeros(n)
    x[:w] = np.hanning(w + 2)[1:-1]
    return hp(x, hpf, 2)


def smooth_rand(n, rate_hz, rng):
    """Smooth random control signal in [-1, 1]: random points at `rate_hz`, cosine-interpolated."""
    k = max(3, int(np.ceil(n / SR * rate_hz)) + 2)
    pts = rng.uniform(-1, 1, k)
    pos = np.arange(n) / SR * rate_hz
    i = np.floor(pos).astype(int)
    f = pos - i
    w = (1 - np.cos(np.pi * f)) / 2
    return pts[i] * (1 - w) + pts[i + 1] * w


def poisson_times(dur, rate, rng):
    t, out = 0.0, []
    while True:
        t += rng.exponential(1.0 / rate)
        if t >= dur:
            return np.array(out)
        out.append(t)


def grains(dur, rate, rng, lo=1500, hi=9000, glen=0.003, env_tau=None, amp_sd=0.6):
    """Sparse micro-impacts (debris, grit, crackle)."""
    n = secs(dur)
    x = np.zeros(n)
    times = poisson_times(dur, rate, rng)
    gl = max(8, secs(glen))
    for t in times:
        s = secs(t)
        a = np.exp(rng.normal(0, amp_sd))
        if env_tau:
            a *= np.exp(-t / env_tau)
        g = rng.standard_normal(gl) * np.exp(-np.arange(gl) / (gl / 4))
        e = min(n, s + gl)
        x[s:e] += a * g[: e - s]
    return bp(x, lo, hi, 2)


# ----------------------------------------------------------------------------- dynamics
def softclip(x, drive=1.5):
    return np.tanh(drive * x) / np.tanh(drive)


def compress(x, thr_db=-18, ratio=4.0, att_ms=1.0, rel_ms=80.0, knee_db=6.0, makeup_db=0.0):
    """Feed-forward peak compressor (stereo-linked)."""
    det = np.abs(x).max(1) if x.ndim == 2 else np.abs(x)
    a_att = np.exp(-1.0 / (att_ms * 1e-3 * SR))
    a_rel = np.exp(-1.0 / (rel_ms * 1e-3 * SR))
    env = np.empty_like(det)
    e = 0.0
    for i, v in enumerate(det):
        e = a_att * e + (1 - a_att) * v if v > e else a_rel * e + (1 - a_rel) * v
        env[i] = e
    lvl = 20 * np.log10(env + 1e-9)
    over = lvl - thr_db
    gr = np.where(over <= -knee_db / 2, 0.0,
                  np.where(over >= knee_db / 2, over * (1 - 1 / ratio),
                           (1 - 1 / ratio) * (over + knee_db / 2) ** 2 / (2 * knee_db)))
    g = 10 ** ((-gr + makeup_db) / 20)
    return x * (g[:, None] if x.ndim == 2 else g)


def transient_shape(x, attack_db=6.0, sustain_db=0.0, fast_ms=1.0, slow_ms=30.0):
    """Classic differential-envelope transient designer."""
    det = np.abs(mono(x))
    ef = signal.lfilter([1 - np.exp(-1 / (fast_ms * 1e-3 * SR))], [1, -np.exp(-1 / (fast_ms * 1e-3 * SR))], det)
    es = signal.lfilter([1 - np.exp(-1 / (slow_ms * 1e-3 * SR))], [1, -np.exp(-1 / (slow_ms * 1e-3 * SR))], det)
    d = np.clip((ef - es) / (ef + 1e-9), 0, 1)
    g = db2a(attack_db * d + sustain_db * (1 - d))
    return x * (g[:, None] if x.ndim == 2 else g)


# ----------------------------------------------------------------------------- time / edits
def resample_ratio(x, ratio):
    """Play back `ratio` times faster (ratio>1 => higher pitch, shorter)."""
    if abs(ratio - 1) < 1e-4:
        return x
    fr = Fraction(1 / ratio).limit_denominator(160)
    return signal.resample_poly(x, fr.numerator, fr.denominator, axis=0)


def resample_to(x, sr_in):
    if sr_in == SR:
        return x
    fr = Fraction(SR, sr_in).limit_denominator(1000)
    return signal.resample_poly(x, fr.numerator, fr.denominator, axis=0)


def fade(x, fin=0.0, fout=0.0):
    x = x.copy()
    n = len(x)
    if fin > 0:
        k = min(n, secs(fin))
        w = np.sin(np.linspace(0, np.pi / 2, k)) ** 2
        x[:k] *= w[:, None] if x.ndim == 2 else w
    if fout > 0:
        k = min(n, secs(fout))
        w = np.cos(np.linspace(0, np.pi / 2, k)) ** 2
        x[n - k:] *= w[:, None] if x.ndim == 2 else w
    return x


def trim(x, thr_db=-66.0, lead=True, tail=True, pre=0.0005, fout=0.03):
    """Trim silence relative to peak; fade the tail out cleanly."""
    a = np.abs(x).max(1) if x.ndim == 2 else np.abs(x)
    thr = a.max() * db2a(thr_db)
    idx = np.where(a > thr)[0]
    if len(idx) == 0:
        return x
    s = max(0, idx[0] - secs(pre)) if lead else 0
    # tail: find last sample where a smoothed envelope exceeds threshold
    sm = signal.lfilter([1 - 0.999], [1, -0.999], a)
    idx2 = np.where(sm > thr * 0.5)[0]
    e = min(len(x), idx2[-1] + secs(0.01)) if tail and len(idx2) else len(x)
    y = x[s:e]
    return fade(y, 0, fout)


def onsets(x, thr_db=-12.0, jump_db=10.0, min_gap=1.0, hop_ms=5.0):
    """Onset times (s) of strong transients (used to slice single shots out of recordings)."""
    m = np.abs(x).max(1) if x.ndim == 2 else np.abs(x)
    hop = int(SR * hop_ms / 1000)
    n = len(m) // hop
    e = m[: n * hop].reshape(n, hop).max(1)
    db = 20 * np.log10(e / (e.max() + 1e-12) + 1e-12)
    out, last = [], -1e9
    if n and db[0] > thr_db:
        out.append(float(np.argmax(m[:hop] > m[:hop].max() * 0.3)) / SR)
        last = 0
    for i in range(1, n):
        if db[i] > thr_db and db[i] - db[i - 1] > jump_db and (i - last) * hop / SR > min_gap:
            # refine to the sample of first large rise within the hop
            seg = m[(i - 1) * hop:(i + 1) * hop]
            j = np.argmax(seg > seg.max() * 0.3)
            out.append(((i - 1) * hop + j) / SR)
            last = i
    return out


def slice_at(x, t, pre=0.002, dur=1.0):
    s = max(0, secs(t - pre))
    return pad(x[s:s + secs(dur + pre)], secs(dur + pre))


def reverse(x):
    return x[::-1].copy()


# ----------------------------------------------------------------------------- space
def make_ir(dur, rt_lo=1.2, rt_hi=0.5, xover=1500.0, predelay=0.0, refl=(), refl_lp=3500.0,
            diffuse_db=0.0, rng=None, st=True, build=0.015, lo_cut=120.0):
    """Synthetic outdoor/room impulse response.

    Diffuse tail = decorrelated noise split in two bands with different RT60 (HF dies faster),
    plus discrete slap-back reflections (t_sec, gain_db, pan -1..1) low-passed (buildings absorb HF).
    """
    n = secs(dur)
    t = tvec(n)
    chs = 2 if st else 1
    out = np.zeros((n, chs))
    for c in range(chs):
        w = rng.standard_normal(n)
        lo = lp(w, xover, 2) * np.exp(-6.91 * t / rt_lo)
        hi = hp(w, xover, 2) * np.exp(-6.91 * t / rt_hi)
        d = (lo + hi) * db2a(diffuse_db) * (1 - np.exp(-t / build))
        out[:, c] = d * 0.12
    if lo_cut:
        out = hp(out, lo_cut, 2)
    for (tt, gdb, pan) in refl:
        s = secs(tt)
        if s >= n - 10:
            continue
        g = db2a(gdb)
        gl, gr = np.sqrt(0.5 * (1 - pan)), np.sqrt(0.5 * (1 + pan))
        # a slap-back off a building facade is a smeared, darker copy: short decaying noise cluster,
        # low-passed harder the further (later) it is.
        ln = secs(0.012 + 0.05 * tt)
        fc = refl_lp / (1.0 + 1.5 * tt)
        for c in range(chs):
            k = rng.standard_normal(ln) * np.exp(-np.arange(ln) / (ln / 3.5))
            k[0] += 2.0  # keep a coherent leading edge
            k = lp(k, fc, 4)
            k = k / (np.abs(k).max() + 1e-12) * g * 0.5
            gc = (gl if c == 0 else gr) * 1.41 if chs == 2 else 1.0
            o = s + (int(rng.uniform(0, 0.0008) * SR) if c else 0)
            e = min(n, o + ln)
            out[o:e, c] += k[: e - o] * gc
    if predelay > 0:
        out = np.concatenate([np.zeros((secs(predelay), chs)), out])[:n]
    return out if st else out[:, 0]


def convolve(x, ir):
    """x mono or stereo, ir mono or stereo -> result with max channels."""
    if x.ndim == 1 and ir.ndim == 1:
        return signal.fftconvolve(x, ir)
    xs = stereo(x)
    irs = stereo(ir)
    return np.stack([signal.fftconvolve(xs[:, c], irs[:, c]) for c in range(2)], 1)


def loopify(x, n, xf):
    """Make a seamless loop of length n from a buffer of length >= n+xf (equal-power crossfade)."""
    k = secs(xf)
    assert len(x) >= n + k
    out = x[:n].copy()
    w = np.linspace(0, np.pi / 2, k)
    fi, fo = np.sin(w), np.cos(w)
    if x.ndim == 2:
        fi, fo = fi[:, None], fo[:, None]
    out[:k] = x[:k] * fi + x[n:n + k] * fo
    return out


def pan(x, p):
    """Mono -> stereo with constant-power pan p in [-1, 1]."""
    x = mono(x)
    a = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], 1)
