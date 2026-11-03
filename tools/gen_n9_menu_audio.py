#!/usr/bin/env python3
"""N9 procedural menu SFX (project-original, CC0): the lacquer board of the menu.

menu_open_0.wav   paper rustle as the board lifts, then a soft knock of wood settling
menu_close_0.wav  a shorter rustle and a lower knock as it is set down
menu_tick_0/1.wav a dry paper-and-wood tick for choosing a tab, page or button

Writes 16-bit mono WAVs to assets/audio/sfx/hanabi_proc/. Run: python3 tools/gen_n9_menu_audio.py
"""
import wave
from pathlib import Path

import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets/audio/sfx/hanabi_proc"


def write_wav(path: Path, x: np.ndarray, peak: float = 0.8) -> None:
    x = x / max(1e-9, float(np.max(np.abs(x)))) * peak
    pcm = (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def band_noise(rng, n: int, centre: float, width: float) -> np.ndarray:
    spec = np.fft.rfft(rng.uniform(-1.0, 1.0, n))
    freqs = np.fft.rfftfreq(n, 1.0 / RATE)
    return np.fft.irfft(spec * np.exp(-0.5 * ((freqs - centre) / width) ** 2), n)


def rustle(rng, n: int, centre: float, grain_rate: float) -> np.ndarray:
    """Washi paper: band noise chopped into many tiny crackles."""
    base = band_noise(rng, n, centre, centre * 0.55)
    grains = np.zeros(n)
    count = int(grain_rate * n / RATE)
    for pos in rng.integers(0, n - 400, count):
        length = int(rng.integers(60, 380))
        grains[pos:pos + length] += rng.uniform(0.3, 1.0) * np.exp(-np.arange(length) / (length * 0.3))
    return base * (0.25 + grains)


def knock(n: int, start: float, modes: list[tuple[float, float, float]]) -> np.ndarray:
    """Lacquered wood: a few damped modes after a short felt-soft attack."""
    t = np.arange(n) / RATE
    tt = np.maximum(t - start, 0.0)
    on = (t >= start).astype(float)
    attack = np.clip(tt / 0.0025, 0.0, 1.0)
    out = np.zeros(n)
    for f, a, decay in modes:
        out += a * np.sin(2.0 * np.pi * f * tt) * np.exp(-tt / decay)
    return out * attack * on


def menu_open(seed: int = 91) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = int(0.50 * RATE)
    t = np.arange(n) / RATE
    env = np.clip(t / 0.12, 0.0, 1.0) * np.exp(-np.maximum(t - 0.16, 0.0) / 0.05)
    paper = rustle(rng, n, 3200.0, 900.0) * env * 0.55
    wood = knock(n, 0.215, [(196.0, 1.0, 0.060), (431.0, 0.55, 0.035), (788.0, 0.28, 0.020), (1530.0, 0.10, 0.010)])
    return paper + wood * 0.9


def menu_close(seed: int = 92) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = int(0.36 * RATE)
    t = np.arange(n) / RATE
    env = np.clip(t / 0.03, 0.0, 1.0) * np.exp(-np.maximum(t - 0.05, 0.0) / 0.04)
    paper = rustle(rng, n, 2600.0, 700.0) * env * 0.45
    wood = knock(n, 0.10, [(158.0, 1.0, 0.070), (352.0, 0.5, 0.040), (690.0, 0.22, 0.022)])
    return paper + wood


def menu_tick(seed: int, pitch: float) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = int(0.11 * RATE)
    t = np.arange(n) / RATE
    flick = band_noise(rng, n, 4200.0 * pitch, 1600.0) * np.exp(-t / 0.006)
    wood = knock(n, 0.002, [(1180.0 * pitch, 1.0, 0.016), (2620.0 * pitch, 0.45, 0.008), (540.0 * pitch, 0.35, 0.022)])
    return flick * 0.6 + wood


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    write_wav(OUT / "menu_open_0.wav", menu_open(), 0.78)
    write_wav(OUT / "menu_close_0.wav", menu_close(), 0.72)
    write_wav(OUT / "menu_tick_0.wav", menu_tick(93, 1.0), 0.6)
    write_wav(OUT / "menu_tick_1.wav", menu_tick(94, 1.08), 0.6)
    print("wrote menu_open_0, menu_close_0, menu_tick_0, menu_tick_1 to", OUT)


if __name__ == "__main__":
    main()
