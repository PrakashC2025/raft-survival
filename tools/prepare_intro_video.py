"""Offline preparation of the owner's film; never invoked during gameplay."""
import argparse
import subprocess
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
STARTS = [0.5, 4.0, 6.1, 9.05, 16.0, 19.3, 24.0, 26.7]
DURATION = 31.041667  # 745 constant-rate frames at 24 fps.


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", required=True)
    args = parser.parse_args()
    source = ROOT / "tools/intro_source"
    rate = 22050
    narration = np.zeros(round(DURATION * rate), dtype=np.float32)
    for index, start in enumerate(STARTS):
        with wave.open(str(source / f"narration/line-{index}.wav"), "rb") as clip:
            assert (clip.getframerate(), clip.getnchannels(), clip.getsampwidth()) == (rate, 1, 2)
            samples = np.frombuffer(clip.readframes(clip.getnframes()), dtype="<i2").astype(np.float32)
        end_time = start + len(samples) / rate
        next_time = STARTS[index + 1] if index < 7 else 30.95
        assert end_time < next_time, f"Line {index} overlaps its next scene"
        print(f"Narration {index}: {start:.2f}-{end_time:.2f}s")
        offset = round(start * rate)
        narration[offset:offset + len(samples)] += samples
    narration_path = source / "narration_timed.wav"
    with wave.open(str(narration_path), "wb") as out:
        out.setparams((1, 2, rate, 0, "NONE", "not compressed"))
        out.writeframes(np.clip(narration, -32768, 32767).astype("<i2").tobytes())
    video = ROOT / "video"
    video.mkdir(exist_ok=True)
    # A low-resolution, constant-rate stream avoids runtime interpolation work.
    # Mild denoising reduces WhatsApp compression noise; keep the original marks.
    run = [args.ffmpeg, "-y", "-hide_banner", "-loglevel", "warning"]
    subprocess.run(run + [
        "-i", str(source / "owner_intro.mp4"), "-i", str(narration_path),
        "-filter_complex",
        "[0:v]fps=24,hqdn3d=0.8:0.6:1.2:0.9,pad=848:480:0:1,fade=t=in:st=0:d=0.35[v];"
        "[0:a]volume=0.26[bed];[1:a]loudnorm=I=-16:TP=-2:LRA=7[voice];"
        "[bed][voice]amix=inputs=2:duration=longest:normalize=0,"
        "alimiter=limit=0.95:level=0:latency=1,"
        "afade=t=in:st=0:d=0.25,afade=t=out:st=30.85:d=0.19[a]",
        "-map", "[v]", "-map", "[a]", "-t", str(DURATION),
        "-c:v", "libtheora", "-q:v", "7", "-g:v", "48", "-pix_fmt", "yuv420p",
        "-c:a", "libvorbis", "-q:a", "4", "-ar", "48000", "-ac", "2",
        str(video / "new_game_intro.ogv")], check=True)
    subprocess.run(run + [
        "-ss", "30.85", "-i", str(source / "owner_intro.mp4"),
        "-frames:v", "1", "-update", "1", "-vf", "pad=848:480:0:1", "-q:v", "2",
        str(video / "intro_arrival.jpg")], check=True)


if __name__ == "__main__":
    main()
