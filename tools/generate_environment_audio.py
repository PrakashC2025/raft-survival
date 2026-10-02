"""Generate original seamless ambience beds; the recorded ocean stays primary.

Offline generation keeps sample synthesis out of the Android gameplay loop.
Requires numpy. Run from the project root. No downloaded sound is used here.
"""
from pathlib import Path
import wave
import numpy as np

RATE = 22050
ROOT = Path(__file__).resolve().parents[1] / "audio"


def band_noise(rng, count, low, high, pink=0.0):
    frequencies = np.fft.rfftfreq(count, 1 / RATE)
    spectrum = np.fft.rfft(rng.standard_normal(count))
    safe = np.maximum(frequencies, 1.0)
    shaping = (1 - np.exp(-(safe / low) ** 2)) / (1 + (safe / high) ** 4)
    shaping *= safe ** (-pink)
    shaping[0] = 0
    result = np.fft.irfft(spectrum * shaping, n=count)
    return result / max(np.std(result), 1e-6)


def make(name, seconds, low, high, pink, seed):
    rng = np.random.default_rng(seed)
    count = RATE * seconds
    t = np.arange(count) / RATE
    phase = 2 * np.pi * t / seconds
    common = band_noise(rng, count, low, high, pink)
    channels = []
    for side in range(2):
        detail = band_noise(rng, count, low, high, pink)
        envelope = 0.64 + 0.18 * np.sin(phase + side * 0.3) + 0.12 * np.sin(phase * 3 + 1.2)
        if name == "foliage_rustle":
            envelope *= 0.45 + 0.55 * (0.5 + 0.5 * np.sin(phase * 11 + side * 0.7)) ** 2
        channels.append((common * 0.65 + detail * 0.35) * envelope)
    sound = np.stack(channels, axis=1)
    sound *= 0.55 / max(np.max(np.abs(sound)), 1e-6)
    pcm = (np.clip(sound, -1, 1) * 32767).astype("<i2")
    with wave.open(str(ROOT / (name + ".wav")), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())
    print(f"{name}: {seconds}s stereo loop, peak {np.max(np.abs(sound)):.2f}")


if __name__ == "__main__":
    ROOT.mkdir(exist_ok=True)
    make("sea_wind", 16, 65, 2100, 0.45, 240117)
    make("foliage_rustle", 12, 550, 6400, 0.1, 240118)
    make("rain_ambience", 16, 220, 8200, 0.05, 240119)
