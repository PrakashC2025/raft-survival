"""Offline preparation of the owner's film; never invoked during gameplay."""
import argparse
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DURATION = 31.033333  # 931 constant-rate frames at 30 fps.


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", required=True)
    args = parser.parse_args()
    source = ROOT / "tools/intro_source"
    video = ROOT / "video"
    video.mkdir(exist_ok=True)
    # The owner's variable-rate source holds one frame for a second at 15/23s.
    # Stretch the preceding two seconds over each hold, without retiming audio.
    # All optical-flow work happens here, never on the phone. Scene detection
    # preserves hard cuts; the smaller stream offsets the extra decoded frames.
    run = [args.ffmpeg, "-y", "-hide_banner", "-loglevel", "warning"]
    motion = "minterpolate=fps=30:mi_mode=mci:mc_mode=obmc:me_mode=bidir:scd=fdiff:scd_threshold=8"
    # Explicit durations discard the source's one-second final-frame metadata.
    # Interpolate before padding each shot, so cuts never turn into a morph.
    parts = []
    for index, (start, end, rate, length) in enumerate([
        (0, 13, 24, 13), (13, 15, 16, 3), (16, 21, 24, 5),
        (21, 23, 16, 3), (24, 31.1, 24, 7.033333)
    ]):
        parts.append(f"[s{index}]trim=start={start}:end={end},setpts=N/({rate}*TB),"
                     f"{motion},tpad=stop_mode=clone:stop_duration=0.3,trim=duration={length}[v{index}];")
    subprocess.run(run + [
        "-i", str(source / "owner_intro.mp4"),
        "-filter_complex",
        "[0:v]scale=720:406:flags=lanczos,split=5[s0][s1][s2][s3][s4];"
        + "".join(parts) + "[v0][v1][v2][v3][v4]concat=n=5:v=1:a=0,"
        "hqdn3d=0.8:0.6:1.2:0.9,pad=720:408:0:1,fade=t=in:st=0:d=0.35,"
        "tpad=stop_mode=clone:stop_duration=0.2[v];"
        "[0:a]alimiter=limit=0.95:level=0:latency=1,"
        "afade=t=in:st=0:d=0.25,afade=t=out:st=30.85:d=0.19[a]",
        "-map", "[v]", "-map", "[a]", "-t", str(DURATION),
        "-c:v", "libtheora", "-q:v", "7", "-g:v", "30", "-pix_fmt", "yuv420p",
        "-c:a", "libvorbis", "-q:a", "4", "-ar", "48000", "-ac", "2",
        str(video / "new_game_intro.ogv")], check=True)
    subprocess.run(run + [
        "-ss", "30.85", "-i", str(source / "owner_intro.mp4"),
        "-frames:v", "1", "-update", "1", "-vf", "scale=720:406:flags=lanczos,pad=720:408:0:1", "-q:v", "2",
        str(video / "intro_arrival.jpg")], check=True)


if __name__ == "__main__":
    main()
