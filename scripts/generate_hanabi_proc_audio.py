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



def make_furin(dur: float = 2.4) -> list[float]:
    n = int(SR * dur)
    samples = [0.0] * n
    strikes = [
        (0.0, 1760.0, 0.7),
        (0.14, 2349.3, 0.5),
    ]
    for strike_time, base_freq, strike_amp in strikes:
        start_idx = int(SR * strike_time)
        harmonics = [
            (base_freq, 1.0, 1.8),
            (base_freq * 2.76, 0.4, 0.8),
            (base_freq * 5.4, 0.15, 0.4),
            (base_freq * 0.5, 0.12, 1.2),
        ]
        for freq, harm_amp, decay in harmonics:
            for i in range(start_idx, n):
                t = (i - start_idx) / SR
                env = math.exp(-t / decay)
                mod = 1.0 + 0.003 * math.sin(2 * math.pi * 5.5 * t)
                val = harm_amp * strike_amp * env * math.sin(2 * math.pi * freq * mod * t)
                samples[i] += val
    return samples

def mix(*tracks: list[float]) -> list[float]:
    m = max(len(t) for t in tracks)
    out = [0.0] * m
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


# --- Element imbue cues (E3): one short, restrained cue per element -------------

def lowpass(x: list[float], cutoff: float) -> list[float]:
    a = 1.0 - math.exp(-2 * math.pi * cutoff / SR)
    y, out = 0.0, []
    for v in x:
        y += a * (v - y)
        out.append(y)
    return out


def highpass(x: list[float], cutoff: float) -> list[float]:
    low = lowpass(x, cutoff)
    return [v - l for v, l in zip(x, low)]


def partials(freq: float, dur: float, parts: list[tuple[float, float, float]], delay: float = 0.0) -> list[float]:
    """Struck-bell voice: (ratio, amplitude, decay seconds) partials, soft 4 ms attack."""
    n = int(SR * (dur + delay))
    out = [0.0] * n
    start = int(SR * delay)
    for ratio, amp, decay in parts:
        for i in range(start, n):
            t = (i - start) / SR
            env = math.exp(-t / decay) * min(1.0, t / 0.004)
            out[i] += amp * env * math.sin(2 * math.pi * freq * ratio * t)
    return out


def make_imbue_sakura() -> list[float]:
    # Two glass-petal chimes a sixth apart, quiet shimmer on top.
    bell = [(1.0, 1.0, 0.55), (2.76, 0.32, 0.28), (5.4, 0.1, 0.14)]
    a = partials(1318.5, 1.1, bell)
    b = partials(1760.0, 1.1, bell, delay=0.07)
    shimmer = highpass(noise(int(SR * 1.1), 0.05, 5), 5000)
    shimmer = [v * math.exp(-i / SR / 0.25) for i, v in enumerate(shimmer)]
    return mix(a, [v * 0.8 for v in b], shimmer)


def make_imbue_storm() -> list[float]:
    # A short static zip, a dry thump, and a thin high ring.
    n = int(SR * 0.9)
    random.seed(21)
    zip_ = []
    for i in range(int(SR * 0.16)):
        t = i / SR
        env = (t / 0.16) ** 1.5 * math.exp(-t * 9) * 3.0
        zip_.append(env * (random.random() * 2 - 1) * (1.0 if random.random() > 0.55 else 0.25))
    zip_ = highpass(zip_, 1800)
    thump = [math.exp(-i / SR / 0.11) * math.sin(2 * math.pi * (95 - 30 * min(1.0, i / SR / 0.1)) * i / SR) * 0.9 for i in range(int(SR * 0.4))]
    ring = partials(2637.0, 0.8, [(1.0, 0.22, 0.35), (1.5, 0.1, 0.2)], delay=0.12)
    return mix(zip_ + [0.0] * (n - len(zip_)), [0.0] * int(SR * 0.1) + thump, ring)


def make_imbue_ink() -> list[float]:
    # A wet brush drawn across paper, then one dark drop into the inkstone.
    random.seed(33)
    n = int(SR * 0.5)
    brush = lowpass(noise(n, 0.5, 33), 900)
    brush = [v * math.sin(math.pi * i / n) ** 2 for i, v in enumerate(brush)]
    drop = [math.exp(-i / SR / 0.16) * math.sin(2 * math.pi * (150 - 70 * min(1.0, i / SR / 0.18)) * i / SR) * 0.9 for i in range(int(SR * 0.7))]
    return mix([v * 1.4 for v in brush], [0.0] * int(SR * 0.22) + drop)


def make_imbue_shadow() -> list[float]:
    # A held breath: two detuned low tones swelling and sinking, with a hollow overtone.
    n = int(SR * 1.3)
    out = []
    for i in range(n):
        t = i / SR
        env = math.sin(math.pi * min(1.0, t / 1.3)) ** 1.6
        f = 164.8 * (1.0 - 0.06 * t)
        v = math.sin(2 * math.pi * f * t) + 0.9 * math.sin(2 * math.pi * f * 1.007 * t) + 0.25 * math.sin(2 * math.pi * f * 3.0 * t)
        out.append(0.4 * env * v)
    air = lowpass(highpass(noise(n, 0.18, 8), 1200), 4200)
    air = [v * math.sin(math.pi * min(1.0, i / n * 1.4)) ** 2 for i, v in enumerate(air)]
    return mix(out, air)


def make_element_fade() -> list[float]:
    # The blade going quiet: a soft falling tone and a breath of steel.
    n = int(SR * 0.55)
    tone = [0.5 * math.sin(2 * math.pi * (520 - 190 * (i / n)) * i / SR) * (1 - i / n) ** 2 * min(1.0, i / (SR * 0.02)) for i in range(n)]
    hiss = lowpass(highpass(noise(n, 0.12, 12), 2500), 6500)
    hiss = [v * (1 - i / n) ** 3 for i, v in enumerate(hiss)]
    return mix(tone, hiss)


def write_imbue_cues() -> None:
    os.makedirs(OUT, exist_ok=True)
    write_wav(os.path.join(OUT, "imbue_sakura_0.wav"), make_imbue_sakura())
    write_wav(os.path.join(OUT, "imbue_storm_0.wav"), make_imbue_storm())
    write_wav(os.path.join(OUT, "imbue_ink_0.wav"), make_imbue_ink())
    write_wav(os.path.join(OUT, "imbue_shadow_0.wav"), make_imbue_shadow())
    write_wav(os.path.join(OUT, "element_fade_0.wav"), make_element_fade())


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
    write_wav(os.path.join(OUT, "torii_furin_chime.wav"), make_furin())
    write_imbue_cues()
    print("Wrote hanabi_proc audio to", OUT)


if __name__ == "__main__":
    import sys

    if "--imbue-only" in sys.argv:
        write_imbue_cues()  # leaves the older cues byte-identical
        print("Wrote imbue cues to", OUT)
    else:
        main()
