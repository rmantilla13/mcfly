"""PCM helpers in plain Python (no numpy), shared by capture, VAD and TTS.

Audio inside the service is 16 kHz mono signed 16-bit little-endian, moved
around as `bytes` in 80 ms frames.
"""

from __future__ import annotations

import math
import struct
import sys
from array import array

SAMPLE_RATE = 16000
FRAME_SAMPLES = 1280  # 80 ms, what openWakeWord wants per call
FRAME_BYTES = FRAME_SAMPLES * 2

# `level` maps -60…0 dBFS onto 0…1, so normal speech moves the display's orb.
LEVEL_FLOOR_DB = -60.0
# A voice note is at most this long (the service stops recording there).
MAX_NOTE_SECONDS = 30


def samples(pcm: bytes) -> array:
    a = array("h")
    a.frombytes(pcm[: len(pcm) - len(pcm) % 2])
    if sys.byteorder == "big":
        a.byteswap()
    return a


def to_bytes(a: array) -> bytes:
    if sys.byteorder == "big":
        a = array("h", a)
        a.byteswap()
    return a.tobytes()


def rms(pcm: bytes) -> float:
    """Root mean square of the samples, 0.0 (silence) to 1.0 (full scale)."""
    a = samples(pcm)
    if not a:
        return 0.0
    return math.sqrt(sum(s * s for s in a) / len(a)) / 32768.0


def level(rms_value: float) -> float:
    if rms_value <= 0.0:
        return 0.0
    db = 20.0 * math.log10(rms_value)
    return min(1.0, max(0.0, (db - LEVEL_FLOOR_DB) / -LEVEL_FLOOR_DB))


def pick_channel(pcm: bytes, channels: int, channel: int) -> bytes:
    """One channel out of interleaved multi-channel audio."""
    if channels == 1:
        return pcm
    return to_bytes(samples(pcm)[channel::channels])


def parse_wav(data: bytes) -> tuple[int, int, bytes]:
    """(sample rate, channels, pcm) from a 16-bit PCM WAV. Tolerates the
    placeholder sizes espeak-ng writes when it streams to stdout."""
    if len(data) < 12 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError("not a WAV file")
    pos = 12
    fmt: tuple[int, int] | None = None
    while pos + 8 <= len(data):
        chunk_id = data[pos : pos + 4]
        size = struct.unpack_from("<I", data, pos + 4)[0]
        body = pos + 8
        if chunk_id == b"fmt ":
            audio_format, channels, rate, _, _, bits = struct.unpack_from("<HHIIHH", data, body)
            if audio_format not in (1, 0xFFFE) or bits != 16:
                raise ValueError(f"unsupported WAV format {audio_format}/{bits}-bit")
            fmt = (rate, channels)
        elif chunk_id == b"data":
            if fmt is None:
                raise ValueError("WAV data before format")
            end = len(data) if size == 0 else min(len(data), body + size)
            pcm = data[body:end]
            frame = 2 * fmt[1]
            return fmt[0], fmt[1], pcm[: len(pcm) - len(pcm) % frame]
        pos = body + size + (size & 1)
    raise ValueError("WAV has no audio data")


def tone(freq: float, seconds: float, amplitude: float = 0.3, rate: int = SAMPLE_RATE) -> bytes:
    """A sine tone, for tests."""
    n = int(rate * seconds)
    a = array("h", (int(amplitude * 32767 * math.sin(2 * math.pi * freq * i / rate))
                    for i in range(n)))
    return to_bytes(a)


def silence(seconds: float, rate: int = SAMPLE_RATE) -> bytes:
    return bytes(2 * int(rate * seconds))


def to_wav(pcm: bytes, rate: int = SAMPLE_RATE) -> bytes:
    """16-bit mono PCM as a WAV file (a voice note)."""
    import io
    import wave

    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm[: len(pcm) - len(pcm) % 2])
    return buf.getvalue()


def from_wav(data: bytes) -> tuple[int, bytes]:
    """A 16-bit PCM WAV's sample rate and its samples as mono (a stereo one
    mixed down). The `wave` module walks the chunks, so a file with others
    before its data (the iPhone pads one) reads too. ValueError otherwise."""
    import io
    import wave

    try:
        with wave.open(io.BytesIO(data), "rb") as w:
            channels, width, rate = w.getnchannels(), w.getsampwidth(), w.getframerate()
            frames = w.readframes(w.getnframes())
    except (wave.Error, EOFError) as e:
        raise ValueError(f"not a WAV file ({e})") from None
    if width != 2:
        raise ValueError("only 16-bit WAV plays")
    if not 8000 <= rate <= 48000:
        raise ValueError(f"a sample rate of {rate} Hz doesn't play")
    if channels == 2:
        a = samples(frames)
        mono = array("h", ((a[i] + a[i + 1]) // 2 for i in range(0, len(a) - 1, 2)))
        frames = to_bytes(mono)
    elif channels != 1:
        raise ValueError(f"{channels} channels don't play")
    return rate, frames
