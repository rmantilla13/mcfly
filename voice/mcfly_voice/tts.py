"""Text to speech, all run locally: Kokoro-82M (the voice Homestead speaks
with, "Heart" by default), else Piper, else the espeak-ng command line."""

from __future__ import annotations

import ctypes.util
import hashlib
import logging
import queue
import re
import shutil
import subprocess
import threading
import urllib.request
from collections.abc import Callable, Iterator
from pathlib import Path
from typing import Any, Protocol

from .audio import Player
from .config import KOKORO_VOICES, TtsConfig
from .pcm import parse_wav, pick_channel

log = logging.getLogger(__name__)

_URL = re.compile(r"https?://\S+")
_EMPHASIS = re.compile(r"(\*\*|__|\*)(\S(?:.*?\S)?)\1")
_LIST_MARK = re.compile(r"^\s*(?:#+|[-*•]|\d+[.)])\s+")
_EMOJI = re.compile("[\U0001f000-\U0001faff\u2600-\u27bf\u2b00-\u2bff\ufe0f\u200d]")


def clean_for_speech(text: str) -> str:
    """Strip what reads badly aloud: markdown, emoji, URLs. List items become
    short sentences."""
    text = _URL.sub("a link", text).replace("`", "")
    lines = [_EMOJI.sub("", _EMPHASIS.sub(r"\2", _LIST_MARK.sub("", line))).strip()
             for line in text.splitlines()]
    lines = [line for line in lines if line]
    if len(lines) > 1:
        # A pause between items instead of running them together.
        lines = [line if line[-1] in ".!?,;:" else line + "." for line in lines]
    return " ".join(" ".join(lines).split())


class Synthesizer(Protocol):
    engine: str

    def stream(self, text: str) -> tuple[int, Iterator[bytes]]:
        """(sample rate, 16-bit mono chunks) for `text`."""
        ...


# ── Kokoro ──────────────────────────────────────────────────────────────

# The int8 export: the fastest on a Pi's CPU. Pinned by hash.
_KOKORO_RELEASE = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"
KOKORO_FILES = {
    "kokoro-v1.0.int8.onnx": "6e742170d309016e5891a994e1ce1559c702a2ccd0075e67ef7157974f6406cb",
    "voices-v1.0.bin": "bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d",
}
KOKORO_RATE = 24000
_PIECE_MAX = 220


def kokoro_dir(data_dir: Path) -> Path:
    return data_dir / "kokoro"


def speech_pieces(text: str) -> list[str]:
    """Sentences, long ones split at commas then words, very short ones merged
    with the next: each renders fast, so the first starts playing quickly."""
    sentences = [s.strip() for s in re.findall(r"[^.!?…]+(?:[.!?…]+[\"”’)]*|$)", text) if s.strip()]
    pieces: list[str] = []
    for s in sentences or [text.strip()]:
        if len(s) <= _PIECE_MAX:
            pieces.append(s)
            continue
        current = ""
        for part in re.split(r"(?<=[,;:])\s+", s):
            for word in part.split(" ") if len(part) > _PIECE_MAX else [part]:
                if current and len((current + " " + word).strip()) > _PIECE_MAX:
                    pieces.append(current.strip())
                    current = ""
                current += " " + word
        if current.strip():
            pieces.append(current.strip())
    merged: list[str] = []
    for p in pieces:
        if merged and len(merged[-1]) < 40 and len(merged[-1]) + 1 + len(p) <= _PIECE_MAX:
            merged[-1] = f"{merged[-1]} {p}"
        else:
            merged.append(p)
    return [p for p in merged if p]


def _system_espeak() -> Any:
    """The system espeak-ng (apt's, on the Pi) for Kokoro's phonemes, or None
    to use the copy kokoro-onnx bundles."""
    from kokoro_onnx import EspeakConfig

    lib = ctypes.util.find_library("espeak-ng")
    if not lib:
        for candidate in ("/usr/lib/aarch64-linux-gnu/libespeak-ng.so.1", "/usr/lib/x86_64-linux-gnu/libespeak-ng.so.1",
                          "/opt/homebrew/lib/libespeak-ng.dylib", "/usr/local/lib/libespeak-ng.dylib"):
            if Path(candidate).exists():
                lib = candidate
                break
    data = next((d for d in ("/usr/lib/aarch64-linux-gnu/espeak-ng-data", "/usr/lib/x86_64-linux-gnu/espeak-ng-data",
                             "/usr/share/espeak-ng-data", "/opt/homebrew/share/espeak-ng-data",
                             "/usr/local/share/espeak-ng-data") if Path(d, "phontab").exists()), None)
    return EspeakConfig(lib_path=lib, data_path=data) if lib and data else None


def _render_ahead(pieces: list[str], render: Callable[[str], bytes]) -> Iterator[bytes]:
    """Each piece's audio, rendered one piece ahead on a thread: the next
    sentence is ready when the one playing ends. Stops rendering when the
    caller stops reading (a cancelled reply)."""
    ready: queue.Queue[Any] = queue.Queue(maxsize=1)
    done = threading.Event()
    end = object()

    def produce() -> None:
        try:
            for p in pieces:
                if done.is_set():
                    return
                audio = render(p)
                while not done.is_set():
                    try:
                        ready.put(audio, timeout=0.2)
                        break
                    except queue.Full:
                        continue
        except Exception as e:  # noqa: BLE001 - surfaced to the reader below
            item: Any = e
        else:
            item = end
        while not done.is_set():
            try:
                ready.put(item, timeout=0.2)
                return
            except queue.Full:
                continue

    threading.Thread(target=produce, name="kokoro-render", daemon=True).start()
    try:
        while True:
            item = ready.get()
            if item is end:
                return
            if isinstance(item, Exception):
                raise item
            yield item
    finally:
        done.set()


class KokoroSynth:
    """Kokoro-82M through kokoro-onnx: Homestead's voice, at 24 kHz."""

    engine = "kokoro"

    def __init__(self, cfg: TtsConfig, data_dir: Path) -> None:
        import numpy as np  # noqa: F401 - with the `kokoro` extra
        from kokoro_onnx import Kokoro  # optional: the `kokoro` extra

        folder = kokoro_dir(data_dir)
        model, voices = (folder / name for name in KOKORO_FILES)
        for path in (model, voices):
            if not path.exists():
                raise FileNotFoundError(f"{path} not found (run: python -m mcfly_voice --download-models)")
        self._kokoro = Kokoro(str(model), str(voices), espeak_config=_system_espeak())
        self.rate = KOKORO_RATE
        self.voice = cfg.kokoro_voice if cfg.kokoro_voice in KOKORO_VOICES else "af_heart"
        self.speed = min(2.0, max(0.5, cfg.speed))
        self._volume = cfg.volume
        log.info("spoken replies: kokoro, voice %s", self.voice)

    def set_voice(self, voice: str) -> None:
        if voice in KOKORO_VOICES:
            self.voice = voice

    def set_speed(self, speed: float) -> None:
        self.speed = min(2.0, max(0.5, float(speed)))

    def _render(self, text: str, voice: str, speed: float) -> bytes:
        import numpy as np

        samples, _ = self._kokoro.create(text, voice=voice, speed=speed, lang="en-us")
        pcm = np.clip(np.asarray(samples, dtype=np.float32) * self._volume, -1.0, 1.0)
        return (pcm * 32767).astype("<i2").tobytes()

    def stream(self, text: str) -> tuple[int, Iterator[bytes]]:
        voice, speed = self.voice, self.speed  # a change mid-reply applies to the next one
        return self.rate, _render_ahead(speech_pieces(text), lambda p: self._render(p, voice, speed))


def download_kokoro(data_dir: Path, opener: Callable[[str], Any] = urllib.request.urlopen) -> None:
    """Fetches Kokoro's model and voices into <data_dir>/kokoro, checking each
    against its pinned SHA-256. Files already there and correct are kept."""
    folder = kokoro_dir(data_dir)
    folder.mkdir(parents=True, exist_ok=True)
    for name, digest in KOKORO_FILES.items():
        target = folder / name
        if target.exists() and _sha256(target) == digest:
            log.info("kokoro %s already here", name)
            continue
        log.info("downloading kokoro %s", name)
        tmp = target.with_suffix(target.suffix + ".part")
        h = hashlib.sha256()
        with opener(f"{_KOKORO_RELEASE}/{name}") as res, open(tmp, "wb") as out:
            while chunk := res.read(1 << 20):
                h.update(chunk)
                out.write(chunk)
        if h.hexdigest() != digest:
            tmp.unlink(missing_ok=True)
            raise ValueError(f"kokoro {name} didn't match its checksum; try again")
        tmp.replace(target)


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


# ── Piper and espeak-ng ─────────────────────────────────────────────────

def piper_voice_path(voice: str, data_dir: Path) -> Path:
    path = Path(voice).expanduser()
    if path.suffix == ".onnx":
        return path if path.is_absolute() or path.exists() else data_dir / "piper" / path
    return data_dir / "piper" / f"{voice}.onnx"


class PiperSynth:
    engine = "piper"

    def __init__(self, cfg: TtsConfig, data_dir: Path) -> None:
        from piper import PiperVoice  # optional: the `tts` extra

        path = piper_voice_path(cfg.voice, data_dir)
        if not path.exists():
            raise FileNotFoundError(
                f"voice {path} not found (run: python -m mcfly_voice --download-models)")
        self._voice = PiperVoice.load(str(path))
        self.rate = int(self._voice.config.sample_rate)
        self._speed = cfg.speed
        self._volume = cfg.volume
        self._syn = None
        self.set_speed(cfg.speed)
        log.info("spoken replies: piper, voice %s", path.name)

    def set_speed(self, speed: float) -> None:
        self._speed = min(2.0, max(0.5, float(speed)))
        try:
            from piper import SynthesisConfig  # piper-tts 1.3+

            self._syn = SynthesisConfig(length_scale=1.0 / self._speed, volume=self._volume)
        except ImportError:
            self._syn = None

    def stream(self, text: str) -> tuple[int, Iterator[bytes]]:
        if self._syn is not None:
            chunks = (chunk.audio_int16_bytes
                      for chunk in self._voice.synthesize(text, syn_config=self._syn))
        else:  # piper-tts 1.2
            chunks = self._voice.synthesize_stream_raw(text, length_scale=1.0 / self._speed)
        return self.rate, iter(chunks)


class EspeakSynth:
    engine = "espeak-ng"

    def __init__(self, cfg: TtsConfig) -> None:
        exe = shutil.which("espeak-ng") or shutil.which("espeak")
        if exe is None:
            raise FileNotFoundError("espeak-ng isn't installed (apt install espeak-ng)")
        words_per_minute = round(165 * cfg.speed)
        amplitude = min(200, round(100 * cfg.volume))
        self._cmd = [exe, "--stdout", "-v", cfg.espeak_voice,
                     "-s", str(words_per_minute), "-a", str(amplitude)]
        log.info("spoken replies: espeak-ng, voice %s", cfg.espeak_voice)

    def stream(self, text: str) -> tuple[int, Iterator[bytes]]:
        # Text goes in on stdin so a leading "-" can't be read as an option.
        result = subprocess.run(self._cmd, input=text.encode(), capture_output=True,
                                timeout=60, check=False)
        if result.returncode != 0:
            message = result.stderr.decode(errors="replace").strip()
            raise RuntimeError(f"espeak-ng failed: {message}")
        rate, channels, pcm = parse_wav(result.stdout)
        return rate, iter([pick_channel(pcm, channels, 0)])


def create_synth(cfg: TtsConfig, data_dir: Path) -> Synthesizer | None:
    """The configured engine, or None (with a logged reason) if there is none."""
    if cfg.engine == "off":
        log.info("spoken replies are off (tts.engine = off)")
        return None
    problems = []
    if cfg.engine in ("auto", "kokoro"):
        try:
            return KokoroSynth(cfg, data_dir)
        except ImportError:
            problems.append("kokoro-onnx isn't installed")
        except Exception as e:
            problems.append(f"kokoro: {e}")
        if cfg.engine == "auto":
            log.warning("%s; trying piper", problems[-1])
    if cfg.engine in ("auto", "piper"):
        try:
            return PiperSynth(cfg, data_dir)
        except ImportError:
            problems.append("piper isn't installed")
        except Exception as e:
            problems.append(f"piper: {e}")
    if cfg.engine in ("auto", "espeak"):
        if problems:
            log.warning("%s; falling back to espeak-ng", problems[-1])
        try:
            return EspeakSynth(cfg)
        except Exception as e:
            problems.append(str(e))
    log.warning("spoken replies unavailable: %s", "; ".join(problems))
    return None


class Speaker:
    """Speaks one text at a time through a player; `abort` cuts it short."""

    def __init__(self, synth: Synthesizer, player: Player) -> None:
        self.synth = synth
        self.player = player

    def speak(self, text: str, stop: threading.Event) -> None:
        text = clean_for_speech(text)
        if not text or stop.is_set():
            return
        rate, chunks = self.synth.stream(text)
        self.player.play(rate, chunks, stop)

    def abort(self) -> None:
        self.player.abort()
