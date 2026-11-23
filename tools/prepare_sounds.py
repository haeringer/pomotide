#!/usr/bin/env python3
"""Turn raw recordings into the sound files bundled with PomoTide.

Usage: tools/prepare_sounds.py <raw-dir>

<raw-dir> must contain:
  wall-clock.wav                       https://freesound.org/s/353174/ by Kinoton (CC0), mixed to mono
  small-quartz-clock.wav               https://freesound.org/s/369870/ by SpliceSound (CC0), denoised
Both may be any PCM16/24 or float WAV.
  Gong_or_bell_vibrant_(short).wav     https://commons.wikimedia.org/wiki/File:Gong_or_bell_vibrant_(short).ogg (CC0)
  Ocean_Waves_on_a_Tropical_Beach.wav  https://commons.wikimedia.org/wiki/File:Ocean_Waves_on_a_Tropical_Beach.ogg (CC0)
The last two as 16-bit mono 44.1 kHz WAV (afconvert -f WAVE -d LEI16@44100 -c 1 in.ogg out.wav).

Output goes to Resources/Sounds:
  wall_00.wav ...    single ticks, 16-bit at the source sample rate, unfiltered
  quartz_00.wav ...  (even = "tick", odd = "tock" at playback)
  gong.wav           trimmed and normalized gong
bowl.wav is copied by hand: https://freesound.org/s/271370/ by inoshirodesign (CC0), with a fade-out.
  waves.m4a          seamless surf loop for breaks
"""
import array
import math
import struct
import subprocess
import sys
import wave
from pathlib import Path

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "Resources" / "Sounds"


# MARK: WAV I/O for the ticks

def read_any(path):
    """Reads a mono or multichannel PCM/float WAV; returns (samples of channel 1, sample rate)."""
    data = Path(path).read_bytes()
    assert data[:4] == b"RIFF" and data[8:12] == b"WAVE", path
    pos, fmt, raw = 12, None, None
    while pos + 8 <= len(data):
        cid, size = data[pos:pos + 4], struct.unpack("<I", data[pos + 4:pos + 8])[0]
        body = data[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            tag, channels, rate, _, _, bits = struct.unpack("<HHIIHH", body[:16])
            if tag == 0xFFFE:  # WAVE_FORMAT_EXTENSIBLE: real format is in the subformat GUID
                tag = struct.unpack("<H", body[24:26])[0]
            fmt = (tag, channels, rate, bits)
        elif cid == b"data":
            raw = body
        pos += 8 + size + (size & 1)
    tag, channels, rate, bits = fmt
    if tag == 3 and bits == 32:
        values = array.array("f", raw[: len(raw) // 4 * 4])
    elif tag == 1 and bits == 16:
        values = [v / 32768 for v in array.array("h", raw[: len(raw) // 2 * 2])]
    elif tag == 1 and bits == 24:
        values = [int.from_bytes(raw[i:i + 3], "little", signed=True) / 8388608 for i in range(0, len(raw) - 2, 3)]
    else:
        raise ValueError(f"{path}: unsupported WAV format {fmt}")
    return list(values[::channels]), rate


def write16(path, samples, rate):
    """Writes a mono 16-bit WAV at the given sample rate."""
    data = array.array("h", (max(-32767, min(32767, round(s * 32767))) for s in samples))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(data.tobytes())


# MARK: 16-bit I/O for gong and waves

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


# MARK: Processing

def envelope(x, win):
    return [math.sqrt(sum(v * v for v in x[i:i + win]) / win) for i in range(0, len(x) - win, win)]


def fade_out(x, seconds, rate=SR):
    n = min(len(x), int(rate * seconds))
    for i in range(n):
        x[len(x) - n + i] *= 0.5 * (1 + math.cos(math.pi * i / n))
    return x


def slice_ticks(x, rate, count):
    """Cuts single ticks out of a clean recording, without filtering.

    Each tick runs from just before its onset until it has decayed into the
    background (floor + 6 dB), at most 0.6 s, and ends with a short fade.
    """
    win = int(rate * 0.005)
    env = envelope(x, win)
    peak = max(env)
    floor = sorted(env)[len(env) // 2]
    onsets, last = [], -1e9
    for i, e in enumerate(env):
        if e > peak * 0.25 and i * win - last > rate * 0.25:
            onsets.append(i * win)
            last = i * win
    ticks = []
    for k, onset in enumerate(onsets[:count]):
        start = max(0, onset - int(rate * 0.004))
        end = min(start + int(rate * 0.6), onsets[k + 1] - int(rate * 0.01) if k + 1 < len(onsets) else len(x))
        seg = x[start:end]
        e = envelope(seg, win)
        peak_at = e.index(max(e))
        tail = next((i for i in range(peak_at, len(e)) if e[i] < floor * 2), len(e))
        seg = list(seg[: min(len(seg), (tail + 1) * win)])
        ticks.append(fade_out(seg, 0.02, rate))
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
    for old in [*OUT.glob("tick_*.wav"), *OUT.glob("wall_*.wav"), *OUT.glob("quartz_*.wav")]:
        old.unlink()
    # 24 ticks give enough variety; an even count keeps tick/tock pairs intact.
    for prefix, name in (("wall", "wall-clock.wav"), ("quartz", "small-quartz-clock.wav")):
        x, rate = read_any(raw / name)
        ticks = slice_ticks(x, rate, 24)
        for i, t in enumerate(ticks):
            write16(OUT / f"{prefix}_{i:02d}.wav", t, rate)
        print(f"{prefix}: {len(ticks)} ticks at {rate} Hz, {[round(len(t) / rate, 2) for t in ticks]}")
    write(OUT / "gong.wav", prepare_gong(read(raw / "Gong_or_bell_vibrant_(short).wav")))
    if (raw / "Ocean_Waves_on_a_Tropical_Beach.wav").exists():
        tmp = raw / "waves_loop.wav"
        write(tmp, prepare_waves(read(raw / "Ocean_Waves_on_a_Tropical_Beach.wav")))
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", str(tmp), str(OUT / "waves.m4a")], check=True)
        print("waves.m4a written")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
