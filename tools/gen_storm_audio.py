#!/usr/bin/env python3
"""Synthesizes the storm ambience and steel sounds into assets/audio/generated/.

No recordings: everything is filtered noise and inharmonic partials, so the
sounds are license-free placeholders until real foley is recorded (see
README, "Needed assets"). Run from the project root:

    python3 tools/gen_storm_audio.py
"""
import os
import struct
import wave

import numpy as np

SR = 44100
OUT = os.path.join("assets", "audio", "generated")
rng = np.random.default_rng(0x48414E41)


def fft_band(x, lo, hi, tilt=0.0):
    """Band-limit noise in the frequency domain; tilt < 0 darkens (dB/octave)."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    edge = 0.25
    gain = np.clip(np.minimum((f / max(lo, 1.0) - 1.0 + edge) / edge, 1.0), 0.0, 1.0) if lo > 0 else np.ones_like(f)
    gain *= np.clip((hi * (1.0 + edge) - f) / (hi * edge), 0.0, 1.0)
    if tilt:
        gain *= np.power(np.maximum(f, 20.0) / 1000.0, tilt / 6.02)
    return np.fft.irfft(spec * gain, len(x))


def normalize(x, peak=0.89):
    return x * (peak / max(np.max(np.abs(x)), 1e-9))


def write_wav(name, data, loop=False):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    data = np.atleast_2d(data)
    if data.shape[0] < data.shape[1]:
        data = data.T
    frames, channels = data.shape
    pcm = (np.clip(data, -1.0, 1.0) * 32767.0).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm)
    if loop:
        # 'smpl' chunk with one forward loop over the whole file; Godot's WAV
        # importer ("Detect From WAV") picks it up.
        chunk = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        chunk += struct.pack("<6I", 0, 0, 0, frames - 1, 0, 0)
        with open(path, "r+b") as f:
            f.seek(0, 2)
            f.write(b"smpl" + struct.pack("<I", len(chunk)) + chunk)
            size = f.tell() - 8
            f.seek(4)
            f.write(struct.pack("<I", size))
    print("wrote", path, f"{frames / SR:.2f}s", "loop" if loop else "")


def rain_loop(seconds=8.0, fade=1.0):
    n = int(seconds * SR)
    m = int(fade * SR)
    chans = []
    for c in range(2):
        hiss = fft_band(rng.standard_normal(n + m), 400.0, 11000.0, tilt=-2.0)
        body = fft_band(rng.standard_normal(n + m), 120.0, 1400.0, tilt=-3.0) * 0.7
        # Close droplets: short bright ticks on stone and water.
        ticks = np.zeros(n + m)
        for _ in range(int(seconds * 55)):
            p = rng.integers(0, n + m - 600)
            L = rng.integers(120, 500)
            env = np.exp(-np.linspace(0, 7, L))
            freq = rng.uniform(1800, 5200)
            ticks[p:p + L] += np.sin(2 * np.pi * freq * np.arange(L) / SR) * env * rng.uniform(0.05, 0.35)
        x = hiss + body + ticks
        # Slow gusts.
        t = np.arange(n + m) / SR
        x *= 0.85 + 0.15 * np.sin(2 * np.pi * (0.11 + 0.03 * c) * t + c)
        # Seamless loop: crossfade the tail into the head.
        head = x[:m] * np.linspace(0, 1, m) + x[n:n + m] * np.linspace(1, 0, m)
        chans.append(np.concatenate([head, x[m:n]]))
    write_wav("rain_loop.wav", normalize(np.array(chans), 0.7), loop=True)


def thunder(index, seconds=7.0):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    rumble = fft_band(rng.standard_normal(n), 20.0, 260.0, tilt=-6.0)
    crackle = fft_band(rng.standard_normal(n), 300.0, 2500.0, tilt=-4.0)
    env = np.zeros(n)
    # Several rolls of decreasing size, as the sound arrives from different
    # parts of the bolt.
    start = rng.uniform(0.02, 0.12)
    for k in range(rng.integers(3, 6)):
        on = start + k * rng.uniform(0.35, 1.1)
        amp = 0.9 ** k * rng.uniform(0.6, 1.0)
        env += amp * np.clip((t - on) / 0.15, 0, 1) * np.exp(-np.maximum(t - on, 0) / rng.uniform(0.6, 1.4))
    env *= np.clip((seconds - t) / 1.0, 0, 1)
    x = rumble * env + crackle * env * np.exp(-t / 0.8) * 0.18
    write_wav(f"thunder_distant_{index}.wav", normalize(x, 0.85))


def blade_ring(index, seconds=1.6):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    base = rng.uniform(1900, 2600)
    # Inharmonic modes of a thin steel bar.
    ratios = [1.0, 2.76, 5.40, 8.93, 13.34]
    x = np.zeros(n)
    for k, r in enumerate(ratios):
        f = base * r * rng.uniform(0.99, 1.01)
        if f > 18000:
            break
        decay = rng.uniform(0.35, 0.9) / (1 + 0.6 * k)
        beat = 1.0 + 0.004 * np.sin(2 * np.pi * rng.uniform(3, 7) * t)
        x += np.sin(2 * np.pi * f * t * beat + rng.uniform(0, 6.28)) * np.exp(-t / decay) / (1 + k)
    hit = fft_band(rng.standard_normal(n), 2000.0, 14000.0) * np.exp(-t / 0.012) * 0.8
    x = x * np.clip(t / 0.002, 0, 1) + hit
    write_wav(f"blade_ring_{index}.wav", normalize(x, 0.8))


if __name__ == "__main__":
    rain_loop()
    for i in range(3):
        thunder(i)
    for i in range(4):
        blade_ring(i)
