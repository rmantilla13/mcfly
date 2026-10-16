"""The Kokoro engine (Homestead's voice) without the real model: speech
pieces, rendering a piece ahead, voice and speed, downloads checked against
their hashes, and the fallback order."""

from __future__ import annotations

import hashlib
import io
import sys
import threading
import time
import types
from pathlib import Path

import pytest

from mcfly_voice import tts
from mcfly_voice.config import TtsConfig
from mcfly_voice.tts import KokoroSynth, create_synth, download_kokoro, speech_pieces

np = pytest.importorskip("numpy")


def test_speech_pieces():
    assert speech_pieces("Hi. Here is the news.") == ["Hi. Here is the news."]
    long = ("word " * 120 + "end.").strip()
    pieces = speech_pieces(long)
    assert len(pieces) >= 3 and all(len(p) <= 220 for p in pieces)
    assert " ".join(pieces).split() == long.split()
    assert speech_pieces("No full stop") == ["No full stop"]


def test_the_first_piece_is_short_so_speech_starts_soon():
    # Nothing is heard until the first piece has rendered, and on the Pi that
    # takes longer than saying it: it's a clause, not the whole sentence...
    assert speech_pieces("Markets are up today, led by NVDA, after the data-center numbers. Standup is at 9:30.") == [
        "Markets are up today,", "led by NVDA, after the data-center numbers.", "Standup is at 9:30."]
    # ...and a short opening sentence goes alone, not merged into the next.
    assert speech_pieces("Onyx is blocked. What it needs next is App Review's answer on the FSKit entitlement.") == [
        "Onyx is blocked.", "What it needs next is App Review's answer on the FSKit entitlement."]
    # No clause break early on: whole, rather than broken mid-phrase. Numbers
    # and times ("1,000", "9:30") aren't clause breaks.
    whole = "Revenue reached 1,000 units by 9:30 this morning across every single region we track."
    assert speech_pieces(whole) == [whole]
    # Later pieces are as before: short ones still ride with the next.
    text = ("Tomorrow starts with standup at nine, then lunch with Sam. It's short. "
            "The review is at three and runs an hour.")
    assert speech_pieces(text) == [
        "Tomorrow starts with standup at nine,",
        "then lunch with Sam. It's short. The review is at three and runs an hour."]


class FakeKokoro:
    calls: list[tuple[str, str, float]] = []

    def __init__(self, model: str, voices: str, espeak_config=None) -> None:
        self.model, self.voices = model, voices

    def create(self, text: str, voice: str, speed: float, lang: str):
        FakeKokoro.calls.append((text, voice, speed))
        time.sleep(0.02)
        return np.full(2400, 0.5, dtype=np.float32), 24000


@pytest.fixture
def fake_kokoro(monkeypatch, tmp_path):
    module = types.ModuleType("kokoro_onnx")
    module.Kokoro = FakeKokoro
    module.EspeakConfig = lambda **kw: kw
    monkeypatch.setitem(sys.modules, "kokoro_onnx", module)
    FakeKokoro.calls = []
    folder = tmp_path / "kokoro"
    folder.mkdir()
    for name in tts.KOKORO_FILES:
        (folder / name).write_bytes(b"x")
    return tmp_path


def test_kokoro_streams_each_piece_in_order(fake_kokoro):
    synth = KokoroSynth(TtsConfig(kokoro_voice="af_bella", speed=1.2, volume=1.0), fake_kokoro)
    rate, chunks = synth.stream("First sentence is here. Second one follows. And a third, to finish.")
    audio = list(chunks)
    assert rate == 24000
    assert len(audio) == len(FakeKokoro.calls) >= 2
    assert all(v == "af_bella" and s == 1.2 for _, v, s in FakeKokoro.calls)
    assert all(len(a) == 2400 * 2 for a in audio)  # int16 mono
    assert int.from_bytes(audio[0][:2], "little", signed=True) == int(0.5 * 32767)


def test_kokoro_voice_and_speed_change_and_are_bounded(fake_kokoro):
    synth = KokoroSynth(TtsConfig(), fake_kokoro)
    assert synth.voice == "af_heart"
    synth.set_voice("am_fenrir")
    synth.set_voice("robot")  # unknown: kept
    synth.set_speed(5)
    _, chunks = synth.stream("Hello there.")
    list(chunks)
    assert FakeKokoro.calls[-1][1:] == ("am_fenrir", 2.0)


def test_kokoro_stops_rendering_when_the_reply_is_cut(fake_kokoro):
    synth = KokoroSynth(TtsConfig(), fake_kokoro)
    _, chunks = synth.stream(" ".join(f"Sentence number {i} is a little bit longer than forty." for i in range(20)))
    next(chunks)
    chunks.close()  # the player stopped reading
    time.sleep(0.2)
    rendered = len(FakeKokoro.calls)
    time.sleep(0.2)
    assert len(FakeKokoro.calls) == rendered < 20


def test_auto_prefers_kokoro_then_falls_back(fake_kokoro, tmp_path, monkeypatch):
    assert isinstance(create_synth(TtsConfig(), fake_kokoro), KokoroSynth)
    # No model files: piper next (absent here), then espeak-ng (absent): none.
    monkeypatch.setitem(sys.modules, "piper", None)
    monkeypatch.setenv("PATH", str(tmp_path))
    assert create_synth(TtsConfig(), tmp_path / "empty") is None
    assert create_synth(TtsConfig(engine="kokoro"), tmp_path / "empty") is None


def test_download_checks_the_hash(tmp_path, monkeypatch):
    payloads = {name: f"{name} bytes".encode() for name in tts.KOKORO_FILES}
    monkeypatch.setattr(tts, "KOKORO_FILES", {n: hashlib.sha256(b).hexdigest() for n, b in payloads.items()})
    fetched = []

    def opener(url):
        name = url.rsplit("/", 1)[1]
        fetched.append(name)
        return io.BytesIO(payloads[name])

    download_kokoro(tmp_path, opener)
    assert sorted(p.name for p in (tmp_path / "kokoro").iterdir()) == sorted(payloads)
    download_kokoro(tmp_path, opener)  # already there and correct: not fetched again
    assert len(fetched) == 2
    payloads["voices-v1.0.bin"] = b"tampered"
    (tmp_path / "kokoro" / "voices-v1.0.bin").unlink()
    with pytest.raises(ValueError, match="checksum"):
        download_kokoro(tmp_path, opener)
    assert not (tmp_path / "kokoro" / "voices-v1.0.bin").exists()
    assert not list((tmp_path / "kokoro").glob("*.part"))
