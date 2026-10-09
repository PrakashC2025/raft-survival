"""Decode the bundled film offline and catch accidental long in-film freezes."""
import argparse
import re
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--ffmpeg', required=True)
args = parser.parse_args()
film = Path(__file__).resolve().parents[1] / 'video/new_game_intro.ogv'
result = subprocess.run([args.ffmpeg, '-hide_banner', '-i', str(film), '-vf',
                         'freezedetect=n=-50dB:d=0.3', '-an', '-f', 'null', '-'],
                        capture_output=True, text=True, check=True)
log = result.stderr
assert '720x408' in log and '30 fps' in log, 'Unexpected film dimensions or cadence'
start = None
for line in log.splitlines():
    if 'freeze_start:' in line:
        start = float(line.rsplit(':', 1)[1])
    if 'freeze_duration:' in line:
        duration = float(line.rsplit(':', 1)[1])
        assert start is not None and (start > 29.5 or duration < .45), (start, duration)
assert re.search(r'Duration: 00:00:31\.', log), 'Film duration no longer matches captions/audio'
print('INTRO MEDIA: complete decode, 720x408/30fps, 31 seconds, no long freezes before final arrival')
