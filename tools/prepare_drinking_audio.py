"""Prepare one CC0 human sip/swallow recording; no synthesized sound."""
from pathlib import Path
import array
import hashlib
import json
import subprocess
import wave
import zipfile

root = Path(__file__).resolve().parents[1]
archive = root / "build/MoreSounds.zip"
original = zipfile.ZipFile(archive).read("Drink/Drink_05.wav")
raw = root / "build/drink-source.wav"
raw.write_bytes(original)
ffmpeg = root / "tools/media_runtime/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe"
decoded = subprocess.run([str(ffmpeg), "-v", "error", "-i", str(raw), "-f", "s16le", "-ac", "1", "-ar", "22050", "-"], check=True, capture_output=True).stdout
samples = array.array("h", decoded)
peak = max(abs(v) for v in samples)
active = [i for i, value in enumerate(samples) if abs(value) > peak * .015]
start = max(0, active[0]-110)
end = min(len(samples), active[-1]+661)
gain = min(3.0, 26200/max(peak, 1))
output = array.array("h", (int(max(-32767, min(32767, value*gain))) for value in samples[start:end]))
target = root / "audio/contact/drink_sip.wav"
with wave.open(str(target), "wb") as writer:
    writer.setnchannels(1); writer.setsampwidth(2); writer.setframerate(22050); writer.writeframes(output.tobytes())
manifest = {"author":"Ashe Kirk / OwlishMedia", "license":"CC0-1.0", "source":"https://opengameart.org/content/202-more-sound-effects", "download":"https://opengameart.org/sites/default/files/MoreSounds.zip", "member":"Drink/Drink_05.wav", "source_sha256":hashlib.sha256(original).hexdigest(), "runtime_sha256":hashlib.sha256(target.read_bytes()).hexdigest(), "seconds":len(output)/22050, "processing":"mono 22050 Hz PCM; silence trim with attack/tail padding; peak normalization only"}
(root / "audio/contact/drink_sip.source.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf8")
print("Prepared recorded sip/swallow: %.3f seconds"%manifest["seconds"])
