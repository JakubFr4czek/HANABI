#!/usr/bin/env python3
"""D13 procedural SFX (project-original, CC0): steel grab whisper + forest crickets loop.

Writes 16-bit mono WAVs to assets/audio/sfx/hanabi_proc/. Run: python3 tools/gen_d13_audio.py
"""
import wave
from pathlib import Path

import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets/audio/sfx/hanabi_proc"


def write_wav(path: Path, x: np.ndarray) -> None:
    x = x / max(1e-9, float(np.max(np.abs(x)))) * 0.82
    pcm = (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def grab_steel(seed: int = 7) -> np.ndarray:
    # Saya-less grab: a short, bright whisper of steel sliding over a
    # tsuka, plus a faint ring of the blade settling into the palm.
    rng = np.random.default_rng(seed)
    n = int(0.42 * RATE)
    t = np.arange(n) / RATE
    noise = rng.uniform(-1.0, 1.0, n)
    spec = np.fft.rfft(noise)
    freqs = np.fft.rfftfreq(n, 1.0 / RATE)
    band = np.exp(-0.5 * ((freqs - 6200.0) / 2400.0) ** 2)
    whisper = np.fft.irfft(spec * band, n)
    whisper *= np.exp(-np.maximum(t - 0.035, 0.0) / 0.075) * np.clip(t / 0.02, 0.0, 1.0)
    ring = np.zeros(n)
    tr = np.maximum(t - 0.09, 0.0)
    for f, a in [(2180.0, 0.22), (3350.0, 0.13), (5120.0, 0.07)]:
        ring += a * np.sin(2.0 * np.pi * f * tr) * np.exp(-tr / 0.06) * (t >= 0.09)
    x = whisper * 0.9 + ring
    x[-int(0.01 * RATE):] *= np.linspace(1.0, 0.0, int(0.01 * RATE))
    return x


def crickets_loop() -> np.ndarray:
    # 4.0 s exactly periodic (carrier cycles are integers over the loop) so it
    # loops without a seam. Two insects, trills of pulses every 0.5 s.
    loop_s = 4.0
    n = int(loop_s * RATE)
    t = np.arange(n) / RATE
    x = np.zeros(n)
    for carrier, offset, level in [(4700.0, 0.0, 0.10), (5300.0, 0.25, 0.06)]:
        phase_t = np.mod(t - offset, 0.5)  # burst every 0.5 s (8 per loop)
        gate = (phase_t < 0.22).astype(float)
        pulses = np.sin(np.pi * 40.0 * phase_t) ** 2  # 5 pulses per trill
        x += level * gate * pulses * np.sin(2.0 * np.pi * carrier * t)
    rng = np.random.default_rng(3)
    bed = np.fft.rfft(rng.uniform(-1.0, 1.0, n))
    freqs = np.fft.rfftfreq(n, 1.0 / RATE)
    bed = np.fft.irfft(bed * (freqs > 2500.0) * (freqs < 9000.0) / (1.0 + freqs / 3000.0), n)
    x += 0.012 * bed / max(1e-9, float(np.max(np.abs(bed))))
    return x


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    write_wav(OUT / "grab_steel_0.wav", grab_steel())
    write_wav(OUT / "crickets_loop.wav", crickets_loop())
    print("wrote", OUT)
