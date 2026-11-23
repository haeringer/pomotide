#!/usr/bin/env python3
"""Turn raw CC0 recordings into the sound files bundled with PomoTide.

Usage: tools/prepare_sounds.py <raw-dir>

<raw-dir> must contain the two source files from Wikimedia Commons, converted
to 16-bit mono 44.1 kHz WAV (afconvert -f WAVE -d LEI16@44100 -c 1 in.ogg out.wav):
  Clock_(tic_tac).wav               https://commons.wikimedia.org/wiki/File:Clock_(tic_tac).ogg
  Gong_or_bell_vibrant_(short).wav  https://commons.wikimedia.org/wiki/File:Gong_or_bell_vibrant_(short).ogg

Output goes to Resources/Sounds:
  tick_00.wav ... tick_NN.wav  one file per tick, in recording order
                               (even = "tick", odd = "tock" at playback)
  gong.wav                     trimmed and normalized gong
"""
import array
import math
import sys
import wave
from pathlib import Path

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "Resources" / "Sounds"


def read(path):
    with wave.open(str(path)) as w:
        assert w.getframerate() == SR and w.getnchannels() == 1 and w.getsampwidth() == 2, path
        return [s / 32768 for s in array.array("h", w.readframes(w.getnframes()))]


def write(path, samples):
    data = array.array("h", (max(-32767, min(32767, int(s * 32767))) for s in samples))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def envelope(x, win):
    return [math.sqrt(sum(v * v for v in x[i:i + win]) / win) for i in range(0, len(x) - win, win)]


def fade_out(x, seconds):
    n = min(len(x), int(SR * seconds))
    for i in range(n):
        x[len(x) - n + i] *= 0.5 * (1 + math.cos(math.pi * i / n))
    return x


def slice_ticks(x):
    win = int(SR * 0.005)
    env = envelope(x, win)
    peak = max(env)
    onsets, last = [], -1e9
    for i, e in enumerate(env):
        if e > peak * 0.25 and i * win - last > SR * 0.25:
            onsets.append(i * win)
            last = i * win
    ticks = []
    for k, start in enumerate(onsets):
        start = max(0, start - int(SR * 0.004))
        end = min(start + int(SR * 0.45), onsets[k + 1] - int(SR * 0.01) if k + 1 < len(onsets) else len(x))
        seg = x[start:end]
        # Cut the tail once the tick has decayed below 3 % of its peak.
        e = envelope(seg, win)
        p = max(e)
        tail = next((i for i in range(len(e) - 1, 0, -1) if e[i] > p * 0.03), len(e) - 1)
        seg = seg[: min(len(seg), (tail + 2) * win)]
        ticks.append(fade_out(seg, 0.04))
    # One gain for the whole set keeps the natural loudness differences between ticks.
    g = 0.89 / max(abs(v) for t in ticks for v in t)
    return [[v * g for v in t] for t in ticks]


def prepare_gong(x):
    p = max(abs(v) for v in x)
    start = next(i for i, v in enumerate(x) if abs(v) > p * 0.02)
    seg = x[max(0, start - int(SR * 0.005)):]
    g = 0.7 / p
    return fade_out([v * g for v in seg], 1.0)


def main(raw):
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("tick_*.wav"):
        old.unlink()
    ticks = slice_ticks(read(raw / "Clock_(tic_tac).wav"))
    for i, t in enumerate(ticks):
        write(OUT / f"tick_{i:02d}.wav", t)
    write(OUT / "gong.wav", prepare_gong(read(raw / "Gong_or_bell_vibrant_(short).wav")))
    print(f"{len(ticks)} ticks, lengths {[round(len(t) / SR, 2) for t in ticks]}")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
