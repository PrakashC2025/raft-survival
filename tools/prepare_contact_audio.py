"""Prepare CC0 recordings with immediate contact attacks and natural tails.

Sources must already be downloaded into build/audio-source. No sound synthesis.
Outputs are small, preloaded mono PCM clips, with an auditable source manifest.
"""
from pathlib import Path
import array
import hashlib
import json
import subprocess
import wave

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "build/audio-source"
OUT = ROOT / "audio/contact"
FFMPEG = ROOT / "tools/media_runtime/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe"
OUT.mkdir(parents=True, exist_ok=True)
clips = {}
for group, prefix in {"grass": "footstep_grass", "snow": "footstep_snow", "stone": "footstep_concrete", "metal": "impactMetal_light", "casing": "impactGeneric_light"}.items():
    for i in range(3):
        clips[f"{group}{i + 1}"] = SOURCE / f"kenney-impact/Audio/{prefix}_{i:03}.ogg"
for i in range(1, 4):
    clips[f"wood{i}"] = SOURCE / f"tinyworlds/wood0{i}.ogg"
clips["sand1"] = SOURCE / "tinyworlds/gravel.ogg"
clips["sand2"] = SOURCE / "tinyworlds/mud02.ogg"
clips["cloth"] = ROOT / "audio/pickup_rustle.ogg"
clips["hammer"] = ROOT / "audio/chop.ogg"
manifest = []
for name, source in clips.items():
    decoded = subprocess.run([str(FFMPEG), "-v", "error", "-i", str(source), "-f", "s16le", "-ac", "1", "-ar", "22050", "-"], check=True, capture_output=True).stdout
    samples = array.array("h", decoded)
    peak = max(abs(v) for v in samples)
    threshold = max(80, int(peak * .018))
    first = next(i for i, v in enumerate(samples) if abs(v) >= threshold)
    last = max(i for i, v in enumerate(samples) if abs(v) >= threshold)
    # Keep 0.5 ms before contact and 60 ms after the audible decay.
    start = max(0, first - 11)
    samples = samples[start:min(len(samples), last + 1323)]
    gain = min(2.0, 24500 / peak)
    samples = array.array("h", (int(v * gain) for v in samples))
    for i in range(min(11, len(samples))):
        samples[i] = int(samples[i] * i / 11)
        samples[-1-i] = int(samples[-1-i] * i / 11)
    destination = OUT / f"{name}.wav"
    with wave.open(str(destination), "wb") as writer:
        writer.setnchannels(1); writer.setsampwidth(2); writer.setframerate(22050)
        writer.writeframes(samples.tobytes())
    manifest.append({"file": destination.relative_to(ROOT).as_posix(), "source": source.relative_to(ROOT).as_posix(), "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "leading_removed_ms": round(start / 22.05, 2), "contact_onset_ms": round((first-start) / 22.05, 2), "seconds": round(len(samples)/22050, 4), "license": "CC0-1.0"})
(OUT / "source_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(f"Prepared {len(manifest)} recorded contact clips; maximum attack padding {max(c['contact_onset_ms'] for c in manifest)} ms")
