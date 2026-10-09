"""Original quiet action foley. Offline synthesis; no runtime DSP or downloads."""
from pathlib import Path
import wave
import numpy as np

RATE = 22050
ROOT = Path(__file__).resolve().parents[1] / 'audio'


def write(name, seconds, seed):
    rng = np.random.default_rng(seed)
    t = np.arange(int(seconds * RATE)) / RATE
    noise = rng.standard_normal(len(t))
    smooth = np.convolve(noise, np.ones(9) / 9, mode='same')
    sound = np.zeros(len(t))
    if name == 'stone':
        sound = (noise * .45 + np.sin(t*2*np.pi*2710)*.5 + np.sin(t*2*np.pi*4100)*.18) * np.exp(-t*85)
    elif name == 'bite':
        for start, size in [(0.015, 1), (.07, .55), (.13, .30), (.22, .17)]:
            age = np.maximum(t - start, 0)
            sound += (noise * .6 + smooth) * np.exp(-age * 48) * (t >= start) * size
    elif name == 'sip':
        envelope = np.sin(np.pi * t / seconds) ** 2
        sound = smooth * envelope * (.6 + .3 * np.sin(t * 2 * np.pi * 17))
        sound += np.sin(2*np.pi*(170*t+35*t*t)) * envelope * .06
    elif name == 'stir':
        sound = smooth * np.sin(np.pi * t / seconds) ** 2 * .5
        sound += (np.sin(t*2*np.pi*1370)+.35*np.sin(t*2*np.pi*2340)) * np.exp(-t*45) * .06
    elif name == 'sizzle':
        sound = noise * .12 + smooth * (.28 + .09*np.sin(t*2*np.pi*3))
        for start in rng.uniform(.1, seconds-.1, 35):
            age = np.maximum(t-start, 0)
            sound += noise * np.exp(-age*140) * (t >= start) * .16
    else:  # Two soft ceramic contacts: cooking completion, without a UI alarm.
        for start, size in [(0.0, 1), (.14, .45)]:
            age = np.maximum(t-start, 0)
            sound += (np.sin(age*2*np.pi*920)+.25*np.sin(age*2*np.pi*1730)) * np.exp(-age*28) * (t >= start) * size
    fade = np.minimum(1, t*250) * np.minimum(1, (seconds-t)*100)
    sound *= fade
    sound *= .48 / max(np.max(np.abs(sound)), 1e-6)
    with wave.open(str(ROOT / ('action_'+name+'.wav')), 'wb') as out:
        out.setnchannels(1); out.setsampwidth(2); out.setframerate(RATE)
        out.writeframes((sound*32767).astype('<i2').tobytes())
    print(name, len(t), 'samples')


if __name__ == '__main__':
    import sys
    if '--fire' in sys.argv:
        write('stone', .18, 91248)
        sys.exit(0)
    for index, (name, seconds) in enumerate([('bite', .34), ('sip', .42), ('stir', .32), ('sizzle', 3), ('ready', .45)]):
        write(name, seconds, 89110+index)
