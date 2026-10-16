"""Wake word: openWakeWord scoring, plus the gate that decides when a
detection is allowed to start a session."""

from __future__ import annotations

import logging
import math
import os
import re
import time
from collections.abc import Callable
from pathlib import Path

log = logging.getLogger(__name__)

MODEL_SUFFIXES = (".onnx", ".tflite")
# McFly's own wake words ("Hey McFly"), shipped with the package. A copy in
# <data_dir>/wakeword, which --download-models makes, takes precedence.
BUNDLED_DIR = Path(__file__).parent / "wakewords"
# Words display_name can't capitalize by rule.
_SPELLINGS = {"mcfly": "McFly"}


class WakeGate:
    """The wake word only counts when it's on, the service is idle (not
    listening, transcribing or speaking, so it never hears its own voice), at
    least `refractory` seconds after the last detection, and `resume_delay`
    seconds after the last busy spell ended (the room's echo dies down)."""

    def __init__(
        self,
        *,
        enabled: bool = True,
        available: bool = False,
        refractory: float = 2.0,
        resume_delay: float = 0.5,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._enabled = enabled
        self.available = available
        self.refractory = refractory
        self.resume_delay = resume_delay
        self._clock = clock
        self._busy = False
        self._last_trigger = -math.inf
        self._idle_since = -math.inf
        self._needs_reset = True

    @property
    def enabled(self) -> bool:
        return self._enabled

    @enabled.setter
    def enabled(self, value: bool) -> None:
        if value and not self._enabled:
            self._needs_reset = True
        self._enabled = value

    @property
    def active(self) -> bool:
        """Switched on and a model is loaded: what `hello.wakeword` reports."""
        return self._enabled and self.available

    def set_busy(self, busy: bool) -> None:
        if busy == self._busy:
            return
        self._busy = busy
        if busy:
            self._needs_reset = True
        else:
            self._idle_since = self._clock()

    def triggered(self) -> None:
        self._last_trigger = self._clock()
        self._needs_reset = True

    def blocked_by(self) -> str | None:
        """Why a detection would be ignored right now, or None if it wouldn't."""
        if not self._enabled:
            return "disabled"
        if not self.available:
            return "unavailable"
        if self._busy:
            return "busy"
        now = self._clock()
        if now - self._last_trigger < self.refractory:
            return "refractory"
        if now - self._idle_since < self.resume_delay:
            return "resuming"
        return None

    def allows(self) -> bool:
        return self.blocked_by() is None

    def take_reset(self) -> bool:
        """True once after the gate was closed: the detector should drop its
        buffered audio so a stale half-phrase can't fire."""
        reset, self._needs_reset = self._needs_reset, False
        return reset


def display_name(model: str, override: str = "") -> str:
    """What the display shows: 'hey_jarvis_v0.1.onnx' → 'Hey Jarvis',
    'hey_mcfly' → 'Hey McFly'."""
    if override.strip():
        return override.strip()
    stem = Path(model).name
    for suffix in MODEL_SUFFIXES:
        stem = stem.removesuffix(suffix)
    stem = re.sub(r"_v\d+(\.\d+)*$", "", stem)
    words = (w for w in re.split(r"[_\-\s]+", stem) if w)
    return " ".join(_SPELLINGS.get(w.lower(), w.capitalize()) for w in words)


def resolve_model(model: str, framework: str, data_dir: Path) -> tuple[str, str, bool]:
    """(path or built-in name, inference framework, is_path). A file name
    without a directory is looked up in <data_dir>/wakeword. A name prefers a
    copy there (put there by --download-models), then one of McFly's own in
    the package; any other name is openWakeWord's to find."""
    wake_dir = data_dir / "wakeword"
    path = Path(model).expanduser()
    if path.suffix in MODEL_SUFFIXES:
        if not path.is_absolute() and not path.exists():
            path = wake_dir / path
        return str(path), path.suffix[1:], True
    ext = "." + framework
    found = sorted(wake_dir.glob(f"{model}_v*{ext}")) + sorted(wake_dir.glob(f"{model}{ext}"))
    if found:
        return str(found[-1]), framework, True
    bundled = BUNDLED_DIR / f"{model}{ext}"
    if bundled.exists():
        return str(bundled), framework, True
    return model, framework, False


class WakeWordDetector:
    """openWakeWord over 80 ms frames. Not thread-safe; call from one thread."""

    def __init__(self, model: str, *, framework: str = "onnx", data_dir: Path) -> None:
        import numpy as np  # optional: the `wake` extra
        import openwakeword
        from openwakeword.model import Model

        missing = "isn't downloaded (run: python -m mcfly_voice --download-models)"
        target, framework, is_path = resolve_model(model, framework, data_dir)
        if is_path and not Path(target).exists():
            raise FileNotFoundError(f"wake word model not found: {target}")
        if not is_path and any(p.suffix in MODEL_SUFFIXES for p in BUNDLED_DIR.glob(f"{model}.*")):
            raise FileNotFoundError(f"wake word model {model} comes only as .onnx "
                                    "(set wakeword.inference_framework = \"onnx\")")
        if not is_path:
            bundled = [p for p in openwakeword.get_pretrained_model_paths(framework)
                       if model in Path(p).name]
            if not bundled:
                raise ValueError(f"unknown wake word model '{model}' "
                                 f"(built in: {', '.join(openwakeword.MODELS)})")
            if not Path(bundled[0]).exists():
                raise FileNotFoundError(f"wake word model {model} {missing}")
        # The shared feature models: ours if downloaded, else openWakeWord's own.
        feature_dir = data_dir / "wakeword"
        if not (feature_dir / f"melspectrogram.{framework}").exists():
            feature_dir = Path(openwakeword.__file__).parent / "resources" / "models"
        mel = feature_dir / f"melspectrogram.{framework}"
        emb = feature_dir / f"embedding_model.{framework}"
        if not (mel.exists() and emb.exists()):
            raise FileNotFoundError(f"openWakeWord's feature models {missing}")
        kwargs = {"melspec_model_path": str(mel), "embedding_model_path": str(emb)}
        self._np = np
        self._model = Model(wakeword_models=[target], inference_framework=framework, **kwargs)
        self.source = target
        log.info("wake word model: %s (%s)", target, framework)

    def score(self, frame: bytes) -> float:
        scores = self._model.predict(self._np.frombuffer(frame, dtype="<i2"))
        return float(max(scores.values(), default=0.0))

    def reset(self) -> None:
        self._model.reset()


def install_bundled(model: str, target: Path) -> list[Path]:
    """Copy McFly's own wake word `model` from the package into `target`,
    replacing a copy that differs (a retrained model arrives with an update).
    Returns the files written; there are none for openWakeWord's models."""
    written = []
    for src in sorted(BUNDLED_DIR.glob(f"{model}.*")):
        if src.suffix not in MODEL_SUFFIXES:
            continue
        dest = target / src.name
        data = src.read_bytes()
        if dest.exists() and dest.read_bytes() == data:
            continue
        tmp = dest.with_name(dest.name + ".tmp")
        tmp.write_bytes(data)
        os.replace(tmp, dest)
        written.append(dest)
    return written


def download_models(model: str, data_dir: Path) -> None:
    """Put wake word `model` in <data_dir>/wakeword, with the feature models
    every model needs: McFly's own is copied from the package, a built-in
    openWakeWord model is fetched. Custom model files are left alone."""
    if Path(model).suffix in MODEL_SUFFIXES:
        log.info("wake word model %s is a file; nothing to download", model)
        return
    target = data_dir / "wakeword"
    target.mkdir(parents=True, exist_ok=True)
    for path in install_bundled(model, target):
        log.info("installed wake word model %s", path)
    from openwakeword.utils import download_models as oww_download

    # For a name openWakeWord doesn't know (McFly's own) this fetches only the
    # feature models.
    oww_download(model_names=[model], target_directory=str(target))
