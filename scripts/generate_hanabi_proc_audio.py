#!/usr/bin/env python3
"""Regenerate procedural CC0 SFX under assets/audio/sfx/hanabi_proc/."""
import math
import os
import random
import struct
import wave

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx", "hanabi_proc")
SR = 44100


def write_wav(path: str, samples: list[float]) -> None:
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        mx = max(1e-6, max(abs(s) for s in samples))
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s / mx * 0.85)) * 32767)) for s in samples))


def noise(n: int, amp: float = 0.2, seed: int = 42) -> list[float]:
    random.seed(seed)
    return [amp * (random.random() * 2 - 1) for _ in range(n)]


def sine(freq: float, dur: float, amp: float = 0.3, fade_out: float = 0.05) -> list[float]:
    n = int(SR * dur)
    fo = int(SR * fade_out)
    return [
        amp * math.sin(2 * math.pi * freq * t / SR) * (min(1, (n - t) / max(1, fo)) if t > n - fo else 1)
        for t in range(n)
    ]


def mix(*tracks: list[float]) -> list[float]:
    m = max(len(t) for t in tracks)
    out = [0.0] * m
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    write_wav(os.path.join(OUT, "firework_pop_0.wav"), mix(noise(int(SR * 0.35), 0.15), sine(400, 0.35, 0.2, 0.2)))
    write_wav(os.path.join(OUT, "firework_pop_1.wav"), mix(sine(520, 0.28, 0.18, 0.15), noise(int(SR * 0.25), 0.12, 11)))
    write_wav(os.path.join(OUT, "soul_collect_0.wav"), mix(sine(1400, 0.14, 0.25, 0.06), sine(2100, 0.1, 0.15, 0.04)))
    write_wav(os.path.join(OUT, "soul_collect_1.wav"), sine(1800, 0.11, 0.28, 0.05))
    write_wav(os.path.join(OUT, "ofuda_slice_0.wav"), sine(720, 0.22, 0.35, 0.12))
    write_wav(os.path.join(OUT, "level_up_0.wav"), mix(sine(440, 0.45, 0.22, 0.2), sine(554, 0.45, 0.18, 0.2)))
    write_wav(os.path.join(OUT, "yokai_slice_0.wav"), noise(int(SR * 0.09), 0.35, 3))
    n = int(SR * 6)
    wind = []
    random.seed(7)
    phase = 0.0
    for i in range(n):
        phase += 0.0008 + random.random() * 0.0004
        amp = 0.06 + 0.04 * math.sin(2 * math.pi * 0.07 * i / SR)
        wind.append(amp * math.sin(2 * math.pi * phase * 120 + random.random() * 0.5))
    write_wav(os.path.join(OUT, "forest_wind_loop.wav"), wind)
    crack = []
    random.seed(99)
    for i in range(int(SR * 0.45)):
        t = i / SR
        env = math.exp(-t * 6) * (1 - math.exp(-t * 80))
        crack.append(env * (0.4 * math.sin(2 * math.pi * 55 * t) + 0.2 * random.random()))
    write_wav(os.path.join(OUT, "thunder_crack_0.wav"), crack)
    print("Wrote hanabi_proc audio to", OUT)


if __name__ == "__main__":
    main()
