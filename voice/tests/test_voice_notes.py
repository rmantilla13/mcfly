"""Voice notes: recording one from the microphone (`record` → `recorded`)
and playing one (`play`), against the simulated backend."""

from __future__ import annotations

import asyncio
import base64
import io
import json
import wave

import pytest
from helpers import client, fast_sim, running

from mcfly_voice import protocol
from mcfly_voice.pcm import from_wav, to_wav


def wav(seconds: float, rate: int = 16000, channels: int = 1, width: int = 2) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(width)
        w.setframerate(rate)
        w.writeframes(bytes(int(seconds * rate) * channels * width))
    return buf.getvalue()


def quick() -> object:
    return fast_sim(record_step=0.002)


async def test_hello_says_voice_notes_work():
    async with running(quick()) as (_, _, url), client(url, greeted=False) as c:
        hello = await c.recv()
        assert hello["record"] is True and hello["play"] is True


async def test_record_until_stopped_sends_a_wav():
    async with running(quick()) as (service, _, url), client(url) as c:
        await c.send(type="record")
        got = await c.until({"type": "state", "state": "recording"})
        assert got[-1]["state"] == "recording"
        assert service.gate.blocked_by() is not None, "the wake word waits while recording"
        assert service.wake("wakeword") is False
        await c.until({"type": "level"})
        await asyncio.sleep(0.1)  # some seconds of the simulated note
        await c.send(type="stop_record")
        got = await c.until({"type": "recorded"})
        note = got[-1]
        rate, pcm = from_wav(base64.b64decode(note["audio"]))
        assert rate == 16000
        assert note["ms"] == len(pcm) * 1000 // 32000
        assert note["ms"] >= 500
        assert service.state == "idle"


async def test_recording_stops_itself_at_its_length():
    async with running(quick()) as (_, _, url), client(url) as c:
        await c.send(type="record", max_seconds=1)
        got = await c.until({"type": "recorded"})
        assert got[-1]["ms"] == 1000
        assert {"type": "state", "state": "idle"} in [m for m in got if m["type"] == "state"]


async def test_cancel_drops_the_recording():
    async with running(quick()) as (service, _, url), client(url) as c:
        await c.send(type="record")
        await c.until({"type": "state", "state": "recording"})
        await c.send(type="cancel")
        await c.until({"type": "state", "state": "idle"})
        await c.send(type="stop_record")  # nothing to stop: nothing happens
        await c.send(type="speak", text="still here")
        got = await c.until({"type": "spoken"})
        assert "recorded" not in [m["type"] for m in got]
        assert service._recording is None


async def test_one_recording_at_a_time_and_not_while_listening():
    async with running(quick()) as (_, _, url), client(url) as c:
        await c.send(type="record")
        await c.until({"type": "state", "state": "recording"})
        await c.send(type="record")
        got = await c.until({"type": "error"})
        assert got[-1]["message"] == "The microphone is busy; try again in a moment"
        await c.send(type="cancel")


async def test_a_slip_is_too_short_to_send():
    async with running(fast_sim(record_step=0.05)) as (_, _, url), client(url) as c:
        await c.send(type="record")
        await c.until({"type": "state", "state": "recording"})
        await c.send(type="stop_record")
        got = await c.until({"type": "error"})
        assert got[-1]["message"] == "That was too short to send"


async def test_play_a_voice_note_then_spoken():
    backend = quick()
    async with running(backend) as (_, _, url), client(url) as c:
        await c.send(type="play", audio=base64.b64encode(wav(2.0)).decode(), id="note-1")
        got = await c.until({"type": "spoken"})
        assert got[-1] == {"type": "spoken", "id": "note-1"}
        got += await c.until({"type": "state", "state": "idle"})
        assert ["speaking", "idle"] == [m["state"] for m in got if m["type"] == "state"]
        assert backend.played == [(16000, 64000)]


async def test_a_stereo_note_plays_as_mono_and_a_bad_one_says_why():
    backend = quick()
    async with running(backend) as (_, _, url), client(url) as c:
        await c.send(type="play", audio=base64.b64encode(wav(1.0, rate=44100, channels=2)).decode(), id="s")
        await c.until({"type": "spoken", "id": "s"})
        assert backend.played == [(44100, 88200)]
        await c.send(type="play", audio=base64.b64encode(b"not a wav").decode(), id="bad")
        got = await c.until({"type": "spoken", "id": "bad"})
        assert any(m["type"] == "error" and m["message"].startswith("Couldn't play that voice note") for m in got)
        await c.send(type="play", audio=base64.b64encode(wav(1.0, width=1)).decode(), id="8bit")
        got = await c.until({"type": "spoken", "id": "8bit"})
        assert any(m["type"] == "error" and "16-bit" in m["message"] for m in got)


async def test_a_full_length_note_fits_in_one_frame():
    # 30 s at 16 kHz is about 960 KB, 1.3 MB in base64: well inside the frame cap.
    backend = quick()
    async with running(backend) as (_, _, url), client(url) as c:
        await c.ws.send(json.dumps({"type": "play", "audio": base64.b64encode(wav(30.0)).decode(), "id": "long"}))
        await c.until({"type": "spoken", "id": "long"})
        assert backend.played == [(16000, 960000)]


def test_record_and_play_are_checked():
    assert protocol.parse_client_message('{"type": "record"}') == {"type": "record", "max_seconds": 30.0}
    assert protocol.parse_client_message('{"type": "record", "max_seconds": 5}')["max_seconds"] == 5.0
    for bad in (0, 31, True, "10"):
        with pytest.raises(protocol.ProtocolError):
            protocol.parse_client_message(json.dumps({"type": "record", "max_seconds": bad}))
    assert protocol.parse_client_message('{"type": "stop_record"}') == {"type": "stop_record"}
    msg = protocol.parse_client_message(json.dumps({"type": "play", "audio": base64.b64encode(b"x").decode()}))
    assert msg == {"type": "play", "audio": b"x", "id": None}
    for bad in ({"type": "play"}, {"type": "play", "audio": ""}, {"type": "play", "audio": "%%%"},
                {"type": "play", "audio": "eA==", "id": True}):
        with pytest.raises(protocol.ProtocolError):
            protocol.parse_client_message(json.dumps(bad))


def test_wav_round_trip():
    pcm = bytes(range(256)) * 10
    rate, back = from_wav(to_wav(pcm, 16000))
    assert rate == 16000 and back == pcm
    with pytest.raises(ValueError):
        from_wav(b"RIFF....WAVE")
