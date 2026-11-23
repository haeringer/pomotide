#!/usr/bin/env python3
"""Turn raw CC0 recordings into the sound files bundled with PomoTide.

Usage: tools/prepare_sounds.py <raw-dir>

<raw-dir> must contain these CC0 source files, converted to 16-bit mono 44.1 kHz
WAV (afconvert -f WAVE -d LEI16@44100 -c 1 in.ogg out.wav):
  1min_Clock_Ticking.wav               https://freesound.org/s/813355/ by bulkmoerls
                                       (HQ preview, cdn.freesound.org/previews/813/813355_17511816-hq.mp3)
  Gong_or_bell_vibrant_(short).wav     https://commons.wikimedia.org/wiki/File:Gong_or_bell_vibrant_(short).ogg
  Ocean_Waves_on_a_Tropical_Beach.wav  https://commons.wikimedia.org/wiki/File:Ocean_Waves_on_a_Tropical_Beach.ogg

Output goes to Resources/Sounds:
  tick_00.wav ... tick_NN.wav  one file per tick, in recording order
                               (even = "tick", odd = "tock" at playback)
  gong.wav                     trimmed and normalized gong
  waves.m4a                    seamless surf loop for breaks
"""
import array
import math
import subprocess
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


def highpass(x, freq, q=0.7071):
    """RBJ biquad high-pass."""
    w0 = 2 * math.pi * freq / SR
    alpha = math.sin(w0) / (2 * q)
    c = math.cos(w0)
    a0 = 1 + alpha
    b0, b1, b2 = (1 + c) / 2 / a0, -(1 + c) / a0, (1 + c) / 2 / a0
    a1, a2 = -2 * c / a0, (1 - alpha) / a0
    y, x1, x2, y1, y2 = [], 0.0, 0.0, 0.0, 0.0
    for v in x:
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y.append(o)
    return y


def lowpass(x, freq, q=0.7071):
    """RBJ biquad low-pass."""
    w0 = 2 * math.pi * freq / SR
    alpha = math.sin(w0) / (2 * q)
    c = math.cos(w0)
    a0 = 1 + alpha
    b0, b1, b2 = (1 - c) / 2 / a0, (1 - c) / a0, (1 - c) / 2 / a0
    a1, a2 = -2 * c / a0, (1 - alpha) / a0
    y, x1, x2, y1, y2 = [], 0.0, 0.0, 0.0, 0.0
    for v in x:
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y.append(o)
    return y


def soften(tick):
    """Takes the edge off: 4th-order low-pass at 4 kHz and a 2 ms fade-in."""
    tick = lowpass(lowpass(tick, 4000), 4000)
    n = int(SR * 0.002)
    for i in range(min(n, len(tick))):
        tick[i] *= i / n
    return tick


def slice_ticks(x):
    # The recording has rumble and mains hum well below the tick's own spectrum;
    # a 4th-order high-pass at 500 Hz removes it without changing the tick.
    x = highpass(highpass(x, 500), 500)
    win = int(SR * 0.005)
    env = envelope(x, win)
    peak = max(env)
    floor = sorted(env)[len(env) // 2]
    onsets, last = [], -1e9
    for i, e in enumerate(env):
        if e > peak * 0.25 and i * win - last > SR * 0.25:
            onsets.append(i * win)
            last = i * win
    ticks = []
    for k, start in enumerate(onsets):
        start = max(0, start - int(SR * 0.004))
        end = min(start + int(SR * 0.3), onsets[k + 1] - int(SR * 0.01) if k + 1 < len(onsets) else len(x))
        seg = x[start:end]
        # Cut the tail where the tick sinks into the background noise (floor + 6 dB),
        # so no noise is carried from one tick into the silence before the next.
        e = envelope(seg, win)
        peak_at = e.index(max(e))
        tail = next((i for i in range(peak_at, len(e)) if e[i] < floor * 2), len(e))
        seg = seg[: min(len(seg), (tail + 1) * win)]
        ticks.append(fade_out(seg, 0.02))
    # One gain for the whole set keeps the natural loudness differences between ticks.
    g = 0.89 / max(abs(v) for t in ticks for v in t)
    return [[v * g for v in t] for t in ticks]


def prepare_gong(x):
    p = max(abs(v) for v in x)
    start = next(i for i, v in enumerate(x) if abs(v) > p * 0.02)
    seg = x[max(0, start - int(SR * 0.005)):]
    g = 0.7 / p
    return fade_out([v * g for v in seg], 1.0)


def prepare_waves(x):
    """90 s of surf, looped seamlessly with a 4 s crossfade, at a calm level."""
    seg = x[120 * SR:210 * SR + 4 * SR]
    xf = 4 * SR
    body = seg[:-xf]
    tail = seg[-xf:]
    # Equal-power crossfade of the tail into the start, so the end flows into the beginning.
    for i in range(xf):
        t = i / xf
        body[i] = body[i] * math.sin(t * math.pi / 2) + tail[i] * math.cos(t * math.pi / 2)
    rms = math.sqrt(sum(v * v for v in body[::8]) / (len(body) / 8))
    g = 0.06 / rms  # about -24 dBFS RMS; the app volume goes on top
    return [v * g for v in body]


def main(raw):
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("tick_*.wav"):
        old.unlink()
    # 24 ticks give enough variety; an even count keeps tick/tock pairs intact.
    ticks = [soften(t) for t in slice_ticks(read(raw / "1min_Clock_Ticking.wav"))[:24]]
    g = 0.89 / max(abs(v) for t in ticks for v in t)
    ticks = [[v * g for v in t] for t in ticks]
    for i, t in enumerate(ticks):
        write(OUT / f"tick_{i:02d}.wav", t)
    write(OUT / "gong.wav", prepare_gong(read(raw / "Gong_or_bell_vibrant_(short).wav")))
    print(f"{len(ticks)} ticks, lengths {[round(len(t) / SR, 2) for t in ticks]}")
    if (raw / "Ocean_Waves_on_a_Tropical_Beach.wav").exists():
        tmp = raw / "waves_loop.wav"
        write(tmp, prepare_waves(read(raw / "Ocean_Waves_on_a_Tropical_Beach.wav")))
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", str(tmp), str(OUT / "waves.m4a")], check=True)
        print("waves.m4a written")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
