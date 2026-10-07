"""Offline preparation of the owner's film; never invoked during gameplay."""
import argparse
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DURATION = 31.041667  # 745 constant-rate frames at 24 fps.


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", required=True)
    args = parser.parse_args()
    source = ROOT / "tools/intro_source"
    video = ROOT / "video"
    video.mkdir(exist_ok=True)
    # A low-resolution, constant-rate stream avoids runtime interpolation work.
    # Mild denoising reduces WhatsApp compression noise; keep the original marks.
    run = [args.ffmpeg, "-y", "-hide_banner", "-loglevel", "warning"]
    subprocess.run(run + [
        "-i", str(source / "owner_intro.mp4"),
        "-filter_complex",
        "[0:v]fps=24,hqdn3d=0.8:0.6:1.2:0.9,pad=848:480:0:1,fade=t=in:st=0:d=0.35[v];"
        "[0:a]alimiter=limit=0.95:level=0:latency=1,"
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
