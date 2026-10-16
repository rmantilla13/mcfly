"""Wake-word suppression and model naming, without openWakeWord installed."""

from __future__ import annotations

import sys
import tomllib
import types
from pathlib import Path

import pytest

from mcfly_voice import wakeword
from mcfly_voice.config import BUILTIN_WAKEWORDS, Config
from mcfly_voice.wakeword import WakeGate, display_name, resolve_model


class Clock:
    def __init__(self) -> None:
        self.now = 100.0

    def __call__(self) -> float:
        return self.now


def gate(**kwargs) -> tuple[WakeGate, Clock]:
    clock = Clock()
    options = {"enabled": True, "available": True, "refractory": 2.0, "resume_delay": 0.5}
    options.update(kwargs)
    return WakeGate(clock=clock, **options), clock


def test_allows_when_idle_enabled_and_available():
    g, _ = gate()
    assert g.allows() and g.blocked_by() is None and g.active


def test_disabled_or_unavailable_blocks():
    g, _ = gate(enabled=False)
    assert g.blocked_by() == "disabled" and not g.active
    g, _ = gate(available=False)
    assert g.blocked_by() == "unavailable" and not g.active


def test_blocked_while_busy_then_for_resume_delay():
    g, clock = gate()
    g.set_busy(True)  # speaking, or a session in progress
    assert g.blocked_by() == "busy"
    clock.now += 30
    assert g.blocked_by() == "busy"
    g.set_busy(False)
    assert g.blocked_by() == "resuming"
    clock.now += 0.49
    assert not g.allows()
    clock.now += 0.02
    assert g.allows()


def test_refractory_after_a_detection():
    g, clock = gate(resume_delay=0.0)
    g.triggered()
    assert g.blocked_by() == "refractory"
    clock.now += 1.9
    assert g.blocked_by() == "refractory"
    clock.now += 0.2
    assert g.allows()


def test_refractory_outlasts_a_short_session():
    g, clock = gate()
    g.triggered()
    g.set_busy(True)
    clock.now += 1.0
    g.set_busy(False)
    clock.now += 0.6  # past resume_delay, still inside the 2 s refractory
    assert g.blocked_by() == "refractory"
    clock.now += 0.5
    assert g.allows()


def test_detector_reset_is_requested_once_after_each_gap():
    g, clock = gate()
    assert g.take_reset() is True  # fresh start
    assert g.take_reset() is False
    g.set_busy(True)
    g.set_busy(False)
    assert g.take_reset() is True
    assert g.take_reset() is False
    g.triggered()
    assert g.take_reset() is True
    g.enabled = False
    g.take_reset()
    g.enabled = True  # switched back on: stale audio must go
    assert g.take_reset() is True


def test_set_busy_is_idempotent():
    g, clock = gate()
    g.set_busy(False)
    assert g.allows()  # repeating idle doesn't restart resume_delay
    g.set_busy(True)
    clock.now += 5
    g.set_busy(True)
    g.set_busy(False)
    clock.now += 0.6
    assert g.allows()


@pytest.mark.parametrize("model, override, expected", [
    ("hey_jarvis", "", "Hey Jarvis"),
    ("hey_jarvis_v0.1", "", "Hey Jarvis"),
    ("/opt/models/hey_jarvis_v0.1.tflite", "", "Hey Jarvis"),
    ("hey_home_oh_ess.onnx", "", "Hey Home Oh Ess"),
    ("hey_home_oh_ess.onnx", "Hey McFly", "Hey McFly"),
    ("alexa", "  ", "Alexa"),
    ("hey_mcfly", "", "Hey McFly"),
    ("/home/pi/.local/share/mcfly-voice/wakeword/hey_mcfly.onnx", "", "Hey McFly"),
    ("HEY_MCFLY_v2", "", "Hey McFly"),
])
def test_display_name(model, override, expected):
    assert display_name(model, override) == expected


def test_resolve_model(tmp_path):
    wake_dir = tmp_path / "wakeword"
    # A built-in name with nothing downloaded: openWakeWord's own lookup.
    assert resolve_model("hey_jarvis", "onnx", tmp_path) == ("hey_jarvis", "onnx", False)
    wake_dir.mkdir()
    (wake_dir / "hey_jarvis_v0.1.onnx").write_bytes(b"")
    (wake_dir / "hey_jarvis_v0.1.tflite").write_bytes(b"")
    assert resolve_model("hey_jarvis", "onnx", tmp_path) == (
        str(wake_dir / "hey_jarvis_v0.1.onnx"), "onnx", True)
    assert resolve_model("hey_jarvis", "tflite", tmp_path)[0].endswith(".tflite")
    # A bare custom file name lives in <data_dir>/wakeword; its suffix picks the framework.
    assert resolve_model("hey_mcfly.tflite", "onnx", tmp_path) == (
        str(wake_dir / "hey_mcfly.tflite"), "tflite", True)
    custom = tmp_path / "elsewhere.onnx"
    assert resolve_model(str(custom), "tflite", tmp_path) == (str(custom), "onnx", True)


def ship(tmp_path, monkeypatch, data: bytes = b"v1") -> Path:
    """A stand-in for the package's wakewords folder holding hey_mcfly.onnx."""
    shipped = tmp_path / "package"
    shipped.mkdir(exist_ok=True)
    (shipped / "hey_mcfly.onnx").write_bytes(data)
    monkeypatch.setattr(wakeword, "BUNDLED_DIR", shipped)
    return shipped


def test_resolve_model_falls_back_to_the_shipped_wake_word(tmp_path, monkeypatch):
    shipped = ship(tmp_path, monkeypatch)
    data = tmp_path / "data"
    assert resolve_model("hey_mcfly", "onnx", data) == (
        str(shipped / "hey_mcfly.onnx"), "onnx", True)
    # The copy --download-models puts in the data dir wins.
    (data / "wakeword").mkdir(parents=True)
    (data / "wakeword" / "hey_mcfly.onnx").write_bytes(b"copy")
    assert resolve_model("hey_mcfly", "onnx", data)[0] == str(data / "wakeword" / "hey_mcfly.onnx")
    # It ships only as .onnx; tflite is left to openWakeWord, which doesn't know it.
    assert resolve_model("hey_mcfly", "tflite", data) == ("hey_mcfly", "tflite", False)


def test_download_models_copies_the_shipped_wake_word(tmp_path, monkeypatch):
    shipped = ship(tmp_path, monkeypatch)
    (shipped / "hey_mcfly.yaml").write_text("training config, not a model")
    fetched = []
    utils = types.ModuleType("openwakeword.utils")
    utils.download_models = lambda model_names, target_directory: fetched.append(
        (model_names, target_directory))
    monkeypatch.setitem(sys.modules, "openwakeword", types.ModuleType("openwakeword"))
    monkeypatch.setitem(sys.modules, "openwakeword.utils", utils)
    data = tmp_path / "data"
    wake_dir = data / "wakeword"

    wakeword.download_models("hey_mcfly", data)
    assert [p.name for p in wake_dir.iterdir()] == ["hey_mcfly.onnx"]
    assert (wake_dir / "hey_mcfly.onnx").read_bytes() == b"v1"
    # openWakeWord still brings the feature models every wake word needs.
    assert fetched == [(["hey_mcfly"], str(wake_dir))]
    # An update with a retrained model replaces the copy; an unchanged one stays.
    (shipped / "hey_mcfly.onnx").write_bytes(b"v2")
    assert wakeword.install_bundled("hey_mcfly", wake_dir) == [wake_dir / "hey_mcfly.onnx"]
    assert (wake_dir / "hey_mcfly.onnx").read_bytes() == b"v2"
    assert wakeword.install_bundled("hey_mcfly", wake_dir) == []
    # openWakeWord's own are fetched, never copied.
    assert wakeword.install_bundled("hey_jarvis", wake_dir) == []


def test_hey_mcfly_ships_with_the_package():
    assert Config().wakeword.model == "hey_mcfly" == BUILTIN_WAKEWORDS[0]
    assert (wakeword.BUNDLED_DIR / "hey_mcfly.onnx").is_file()
    # And with a wheel install (install-voice.sh), not only from the repo.
    pyproject = tomllib.loads((Path(__file__).resolve().parents[1] / "pyproject.toml").read_text())
    patterns = pyproject["tool"]["setuptools"]["package-data"]["mcfly_voice"]
    model = (wakeword.BUNDLED_DIR / "hey_mcfly.onnx").relative_to(wakeword.BUNDLED_DIR.parent)
    assert any(model.match(p) for p in patterns)
