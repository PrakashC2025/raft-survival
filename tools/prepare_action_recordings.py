"""Prepare small CC0 action samples. No runtime decoding, network or synthesis.

Original downloads are kept in build/audio-source/action-recordings. Only named
archive members are read; archives are never extracted through project paths.
Use --download to fetch the publicly available originals again.
"""
from pathlib import Path
from array import array
import argparse
import hashlib
import io
import json
import subprocess
import urllib.request
import wave
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "build/audio-source/action-recordings"
OUT = ROOT / "audio/contact"
FFMPEG = ROOT / "tools/media_runtime/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe"
PACKS = {
    "rpg": ("rpg.zip", "https://kenney.nl/media/pages/assets/rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip", "https://kenney.nl/assets/rpg-audio", "Kenney"),
    "water": ("water/water-splash-slime-sfx.zip", "https://opengameart.org/sites/default/files/water-splash-slime-sfx.zip", "https://opengameart.org/content/40-cc0-water-splash-slime-sfx", "rubberduck"),
    "eat": ("eat/crunch_-_tito.zip", "https://opengameart.org/sites/default/files/crunch_-_tito.zip", "https://opengameart.org/content/7-eating-crunches", "StarNinjas / Tito"),
    "swish": ("swish/swishes.zip", "https://opengameart.org/sites/default/files/swishes.zip", "https://opengameart.org/content/swishes-sound-pack", "artisticdude"),
    "fire": ("fire/fire.wav", "https://opengameart.org/sites/default/files/fire.wav", "https://opengameart.org/content/fireplace-sound-loop", "PagDev"),
    "boil": ("boil/cooking_with_cover_01.ogg", "https://opengameart.org/sites/default/files/cooking_with_cover_01.ogg", "https://opengameart.org/content/boiling-water-loops", "TinyWorlds"),
    "cook": ("boil/cooking_without_cover_01_0.ogg", "https://opengameart.org/sites/default/files/cooking_without_cover_01_0.ogg", "https://opengameart.org/content/boiling-water-loops", "TinyWorlds"),
    "cut": ("cut/cut_pumpkin_03.ogg", "https://opengameart.org/sites/default/files/cut_pumpkin_03.ogg", "https://opengameart.org/content/cut-peel-a-pumpkin", "TinyWorlds"),
    "swim": ("fish/swim.wav", "https://opengameart.org/sites/default/files/swim.wav", "https://opengameart.org/content/skippy-fish-water-sound-collection", "jcpmcdonald"),
    "water_entry": ("fish/waterReentry.wav", "https://opengameart.org/sites/default/files/waterReentry.wav", "https://opengameart.org/content/skippy-fish-water-sound-collection", "jcpmcdonald"),
    "bubble": ("fish/bubbles.wav", "https://opengameart.org/sites/default/files/bubbles.wav", "https://opengameart.org/content/skippy-fish-water-sound-collection", "jcpmcdonald"),
    "radio": ("radio_static.mp3", "https://opengameart.org/sites/default/files/ScatterNoise1.mp3", "https://opengameart.org/content/static", "xhunterko (authored static effect)"),
}
# name, pack, member, start seconds, maximum seconds, loop
SAMPLES = [
    ("body_impact", "rpg", "Audio/dropLeather.ogg", 0, .50, False),
    ("animal_snap", "rpg", "Audio/knifeSlice2.ogg", 0, .40, False),
    ("bite1", "eat", "crunch.1.ogg", 0, .48, False),
    ("bite2", "eat", "crunch.2.ogg", 0, .48, False),
    ("bite3", "eat", "crunch.3.ogg", 0, .48, False),
    ("water1", "water", "splash_01.ogg", 0, .65, False),
    ("water2", "water", "splash_02.ogg", 0, .65, False),
    ("water3", "water", "splash_03.ogg", 0, .65, False),
    ("swim_stroke", "swim", "", 0, .58, False),
    ("water_entry", "water_entry", "", 0, .45, False),
    ("bubbles", "bubble", "", 0, 1.0, False),
    ("cut_food", "cut", "", 0, .28, False),
    ("stir1", "rpg", "Audio/metalPot1.ogg", 0, .30, False),
    ("stir2", "rpg", "Audio/metalPot2.ogg", 0, .30, False),
    ("stir3", "rpg", "Audio/metalPot3.ogg", 0, .30, False),
    ("handle1", "rpg", "Audio/cloth1.ogg", 0, .30, False),
    ("handle2", "rpg", "Audio/cloth2.ogg", 0, .30, False),
    ("bandage", "rpg", "Audio/clothBelt.ogg", 0, .30, False),
    ("unpack", "rpg", "Audio/clothBelt2.ogg", 0, .42, False),
    ("switch", "rpg", "Audio/metalClick.ogg", 0, .18, False),
    ("battery", "rpg", "Audio/metalLatch.ogg", 0, .26, False),
    ("reel", "rpg", "Audio/creak3.ogg", 0, .30, False),
    ("anchor", "rpg", "Audio/beltHandle1.ogg", 0, .35, False),
    ("draw_tool", "rpg", "Audio/drawKnife1.ogg", 0, .30, False),
    ("door_open", "rpg", "Audio/doorOpen_1.ogg", 0, 1.0, False),
    ("door_close", "rpg", "Audio/doorClose_1.ogg", 0, .70, False),
    ("swing1", "swish", "swishes/swish-1.wav", 0, .40, False),
    ("swing2", "swish", "swishes/swish-2.wav", 0, .40, False),
    ("fire_loop", "fire", "", 2, 10, True),
    ("boil_loop", "boil", "", 0, 6, True),
    ("cook_loop", "cook", "", 0, 6, True),
    ("rain_loop", "water", "loop_rain.ogg", 0, 8, True),
    ("underwater_loop", "water", "loop_bubbles_1.ogg", 0, 6, True),
    ("radio_send", "radio", "", 0, .60, False),
    ("radio_receive", "radio", "", 2, 1.05, False),
]

def digest(data):
    return hashlib.sha256(data).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--download", action="store_true")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.download:
        for path, url, _, _ in PACKS.values():
            dest = RAW / path
            dest.parent.mkdir(parents=True, exist_ok=True)
            if not dest.exists():
                dest.write_bytes(urllib.request.urlopen(url, timeout=60).read())
    records = []
    for name, key, member, start, maximum, loop in SAMPLES:
        path, url, page, author = PACKS[key]
        original = (RAW / path).read_bytes()
        if member:
            with zipfile.ZipFile(io.BytesIO(original)) as archive:
                source = archive.read(member)
        else:
            source = original
        decoded = subprocess.run([str(FFMPEG), "-v", "error", "-i", "pipe:0", "-ac", "1", "-ar", "22050", "-f", "s16le", "pipe:1"], input=source, stdout=subprocess.PIPE, check=True).stdout
        samples = array("h", decoded)
        samples = samples[int(start * 22050):]
        peak = max(abs(v) for v in samples)
        trim = 0
        if not loop:
            threshold = max(70, peak * .02)
            active = [i for i, v in enumerate(samples) if abs(v) >= threshold]
            if not active:
                raise ValueError("Silent source: " + name)
            trim = max(0, active[0] - 11)
            samples = samples[trim:min(len(samples), active[-1] + 661)]
        samples = samples[:int(maximum * 22050)]
        gain = min(3, 24000 / max(1, max(abs(v) for v in samples)))
        samples = array("h", (round(v * gain) for v in samples))
        if loop:
            # Equal-amplitude overlap of real waveforms; no generated noise.
            overlap = min(2646, len(samples) // 8)
            for i in range(overlap):
                mix = i / overlap
                samples[len(samples)-overlap+i] = round(samples[len(samples)-overlap+i]*(1-mix)+samples[i]*mix)
            samples = samples[overlap:]
        else:
            fade = min(22, len(samples) // 4)
            for i in range(fade):
                samples[i] = round(samples[i] * i / fade)
                samples[-1-i] = round(samples[-1-i] * i / fade)
        output = OUT / (name + ".wav")
        with wave.open(str(output), "wb") as wav:
            wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(22050)
            wav.writeframes(samples.tobytes())
        records.append({"file": "res://audio/contact/" + output.name, "license": "CC0-1.0", "author": author, "source_page": page, "download": url, "member": member, "archive_sha256": digest(original), "source_sha256": digest(source), "runtime_sha256": digest(output.read_bytes()), "selected_start_seconds": start, "trim_seconds": trim/22050, "duration_seconds": len(samples)/22050, "loop": loop, "loop_overlap_seconds": .12 if loop else 0, "contact_onset_ms": None if loop else .5})
    (OUT / "action_sources.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")
    print(f"Prepared {len(records)} CC0 action samples ({sum((OUT / Path(r['file']).name).stat().st_size for r in records)/1048576:.2f} MiB)")

if __name__ == "__main__":
    main()
