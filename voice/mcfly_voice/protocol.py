"""The WebSocket protocol between this service and the display: JSON text
frames, one object per frame, each with a `type`. The tables in docs/VOICE.md
are the contract (PLATFORM_SPEC.md §5 points there); the display's
VoiceClient speaks exactly this, so a change here is a change there too."""

from __future__ import annotations

import base64
import binascii
import json
from typing import Any

from . import PROTOCOL_VERSION
from .config import BUILTIN_WAKEWORDS, KOKORO_VOICES
from .pcm import MAX_NOTE_SECONDS

# "recording": a voice note (`record`) has the microphone; the wake word waits.
STATES = ("idle", "listening", "transcribing", "speaking", "recording")
WAKE_SOURCES = ("wakeword", "button")
CLIENT_TYPES = ("listen", "cancel", "speak", "stop_speaking", "set",
                "record", "stop_record", "play")
# A voice note to play, as WAV bytes (30 s of 48 kHz stereo is about 5.8 MB).
MAX_PLAY_BYTES = 6 << 20
# A speak id is echoed in `spoken` to every client.
MAX_ID_CHARS = 200


class ProtocolError(ValueError):
    """A client sent something we can't act on. The message goes back to it."""


# Server → client


def hello(*, wakeword: bool, wakeword_name: str, tts: bool, stt: bool,
          mic: str = "", voice: str = "", speed: float = 1.0,
          wakeword_model: str = "", record: bool = False, play: bool = False) -> dict[str, Any]:
    # `mic` is the open microphone's name, "" when none is open. `voice` is the
    # Kokoro voice ("" when another engine speaks), `speed` the speaking rate,
    # `wakeword_model` the wake word's model. `record` and `play`: voice notes
    # can be recorded (a microphone is open) and played. Clients that predate
    # a key ignore it.
    return {
        "type": "hello",
        "version": PROTOCOL_VERSION,
        "wakeword": wakeword,
        "wakeword_name": wakeword_name,
        "tts": tts,
        "stt": stt,
        "mic": mic,
        "voice": voice,
        "speed": round(float(speed), 2),
        "wakeword_model": wakeword_model,
        "record": record,
        "play": play,
    }


def state(value: str) -> dict[str, Any]:
    assert value in STATES, value
    return {"type": "state", "state": value}


def wake(source: str) -> dict[str, Any]:
    assert source in WAKE_SOURCES, source
    return {"type": "wake", "source": source}


def level(rms: float) -> dict[str, Any]:
    return {"type": "level", "rms": round(min(1.0, max(0.0, rms)), 3)}


def transcript(text: str) -> dict[str, Any]:
    return {"type": "transcript", "text": text, "final": True}


def recorded(wav: bytes, ms: int) -> dict[str, Any]:
    """A voice note, to the client that asked for it: the WAV in base64."""
    return {"type": "recorded", "audio": base64.b64encode(wav).decode("ascii"), "ms": int(ms)}


def spoken(speech_id: str) -> dict[str, Any]:
    return {"type": "spoken", "id": speech_id}


def error(message: str) -> dict[str, Any]:
    return {"type": "error", "message": message}


def encode(message: dict[str, Any]) -> str:
    text = json.dumps(message, ensure_ascii=False, separators=(",", ":"))
    try:
        text.encode()
    except UnicodeEncodeError:
        # A lone surrogate (in a client's id, say) can't be sent as UTF-8; escape it.
        text = json.dumps(message, separators=(",", ":"))
    return text


# Client → server


def parse_client_message(raw: str | bytes) -> dict[str, Any]:
    """Decode and check one client frame. Returns the message with its fields
    normalised; raises ProtocolError with a short reason otherwise."""
    if isinstance(raw, bytes):
        raise ProtocolError("expected a JSON text frame")
    try:
        msg = json.loads(raw)
    except (json.JSONDecodeError, RecursionError):  # RecursionError: absurdly deep nesting
        raise ProtocolError("not valid JSON") from None
    if not isinstance(msg, dict):
        raise ProtocolError("expected a JSON object")
    kind = msg.get("type")
    if kind not in CLIENT_TYPES:
        raise ProtocolError(f"unknown message type {kind!r}")

    if kind == "speak":
        text = msg.get("text")
        if not isinstance(text, str):
            raise ProtocolError("speak needs a text string")
        speech_id = msg.get("id")
        if isinstance(speech_id, bool) or not isinstance(speech_id, (str, int, type(None))):
            raise ProtocolError("speak id must be a string")
        if speech_id is not None:
            speech_id = str(speech_id)
            if len(speech_id) > MAX_ID_CHARS:
                raise ProtocolError(f"speak id must be at most {MAX_ID_CHARS} characters")
        return {"type": "speak", "text": text, "id": speech_id}
    if kind == "record":
        seconds = msg.get("max_seconds", MAX_NOTE_SECONDS)
        if (isinstance(seconds, bool) or not isinstance(seconds, (int, float))
                or not 1 <= seconds <= MAX_NOTE_SECONDS):
            raise ProtocolError(f"max_seconds must be a number from 1 to {MAX_NOTE_SECONDS}")
        return {"type": "record", "max_seconds": float(seconds)}
    if kind == "play":
        audio = msg.get("audio")
        if not isinstance(audio, str) or not audio:
            raise ProtocolError("play needs the audio, a WAV in base64")
        if len(audio) > MAX_PLAY_BYTES * 4 // 3 + 4:
            raise ProtocolError("that audio is too long to play")
        try:
            data = base64.b64decode(audio, validate=True)
        except (binascii.Error, ValueError):
            raise ProtocolError("play's audio isn't base64") from None
        play_id = msg.get("id")
        if isinstance(play_id, bool) or not isinstance(play_id, (str, int, type(None))):
            raise ProtocolError("play id must be a string")
        if play_id is not None:
            play_id = str(play_id)
            if len(play_id) > MAX_ID_CHARS:
                raise ProtocolError(f"play id must be at most {MAX_ID_CHARS} characters")
        return {"type": "play", "audio": data, "id": play_id}
    if kind == "set":
        out: dict[str, Any] = {"type": "set"}
        if "wakeword_enabled" in msg:
            if not isinstance(msg["wakeword_enabled"], bool):
                raise ProtocolError("wakeword_enabled must be true or false")
            out["wakeword_enabled"] = msg["wakeword_enabled"]
        if "voice" in msg:
            if msg["voice"] not in KOKORO_VOICES:
                raise ProtocolError(f"voice must be one of {', '.join(KOKORO_VOICES)}")
            out["voice"] = msg["voice"]
        if "speed" in msg:
            speed = msg["speed"]
            if isinstance(speed, bool) or not isinstance(speed, (int, float)) or not 0.5 <= speed <= 2.0:
                raise ProtocolError("speed must be a number from 0.5 to 2")
            out["speed"] = float(speed)
        if "wakeword_model" in msg:
            if msg["wakeword_model"] not in BUILTIN_WAKEWORDS:
                raise ProtocolError(f"wakeword_model must be one of {', '.join(BUILTIN_WAKEWORDS)}")
            out["wakeword_model"] = msg["wakeword_model"]
        if len(out) == 1:
            raise ProtocolError("set needs wakeword_enabled, voice, speed or wakeword_model")
        return out
    return {"type": kind}
