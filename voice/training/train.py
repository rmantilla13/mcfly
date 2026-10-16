"""Train a McFly wake word with livekit-wakeword 0.3.0 (docs/VOICE.md).

From an empty scratch directory (data and output land there, ~25 GB):

    uv venv --python 3.12 && source .venv/bin/activate
    uv pip install 'livekit-wakeword[train,eval,export]==0.3.0'
    uv pip install --no-deps 'openwakeword>=0.6,<0.7'      # for `check`
    python <repo>/voice/training/train.py <repo>/voice/training/hey_mcfly.yaml all

Stages, in order (`all` runs them all; each picks up where it stopped):
setup (downloads, ~19 GB), generate, augment, extract, train, export, eval,
check. The model is output/<model_name>/<model_name>.onnx; copy it to
voice/mcfly_voice/wakewords/.

Why not livekit-wakeword's own CLI: in 0.3.0 its augment step calls
run_extraction without the session options it requires (fixed after the
release), and the fixes below (speaker shuffle, pauses, weighting the
named near misses) need to run in-process.
"""

from __future__ import annotations

import itertools
import logging
import random
import shutil
import sys
import tempfile
import time
import wave
from pathlib import Path

from livekit.wakeword.config import load_config
from livekit.wakeword.session import session_options

STAGES = ("setup", "generate", "augment", "extract", "train", "export", "eval", "check")
VOICE_DIR = Path(__file__).resolve().parents[1]

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")
log = logging.getLogger("train")


def shuffle_speaker_pairs(seed: int = 7) -> None:
    """Piper synthesis walks speaker pairs as product(range(904), range(904)),
    so the first voice of each blend stays the same for 904 clips in a row and
    20k clips use only ~22 of them. Shuffled (seeded, so a resumed run lines
    up), every batch blends voices from all 904."""
    from livekit.wakeword.data.piper import synthesis

    class Shuffled:
        def __getattr__(self, name):
            return getattr(itertools, name)

        @staticmethod
        def product(*iterables):
            items = list(itertools.product(*iterables))
            if len(iterables) == 2 and all(isinstance(r, range) for r in iterables):
                random.Random(seed).shuffle(items)
            return iter(items)

    synthesis.it = Shuffled()


def keep_pauses() -> None:
    """Let "hey, mcfly" be said with a pause, as people do. Two things in
    livekit-wakeword 0.3.0 take the pause out: espeak-ng --ipa drops clause
    punctuation (Piper voices pause on , and . and piper-phonemize keeps
    them), and remove_silence cuts every quiet 30 ms frame, between words
    too. Keep the punctuation, and trim silence only before and after the
    phrase. Text without punctuation comes out as before."""
    import re

    import numpy as np
    import webrtcvad
    from livekit.wakeword.data.piper import synthesis

    phonemize = synthesis._espeak_phonemize

    def with_punctuation(text: str, voice: str = "en-us") -> str:
        out = ""
        for part in re.split(r"([,.!?;:]+)", text):
            if re.fullmatch(r"[,.!?;:]+", part):
                out = out.rstrip() + part[0] + " "
            elif part.strip():
                out += phonemize(part.strip(), voice) + " "
        return out.strip()

    def trim_edges(x, frame_duration=0.030, sample_rate=16000, min_start=2000):
        if x.dtype in (np.float32, np.float64):
            x = (x * 32767).astype(np.int16)
        vad = webrtcvad.Vad(0)
        step = int(sample_rate * frame_duration)
        speech = [i for i in range(0, len(x) - step, step)
                  if vad.is_speech(x[i:i + step].tobytes(), sample_rate)]
        if not speech:
            return x
        return x[max(0, speech[0] - step):speech[-1] + 2 * step]

    synthesis._espeak_phonemize = with_punctuation
    synthesis.remove_silence = trim_edges


def weight_custom_negatives(config, share: float = 0.25) -> None:
    """run_generate cycles the near misses named in the config together with
    ~8,000 generated sound-alikes, so each named one gets only a few clips.
    Repeat the named ones so they make up `share` of the negative clips:
    they're the phrases most likely to be heard ("hey, fly", "mcfly")."""
    from livekit.wakeword.data import generate

    named = list(config.custom_negative_phrases)
    original = generate.generate_adversarial_phrases

    def weighted(*args, **kwargs):
        phrases = original(*args, **kwargs)
        if named:
            # run_generate appends the named ones once more after this.
            copies = round(share * len(phrases) / ((1 - share) * len(named))) - 1
            phrases = phrases + named * max(0, copies)
            random.Random(11).shuffle(phrases)
        return phrases

    generate.generate_adversarial_phrases = weighted


def check(config) -> None:
    """Scores the held-out 2 s clips the way the Pi does: McFly's own
    WakeWordDetector (openWakeWord, 80 ms frames), against livekit-wakeword's
    scores for the same clips. They should agree; the recall and false
    wakes are at the voice service's default threshold, 0.5."""
    import numpy as np
    from livekit.wakeword import WakeWordModel
    from livekit.wakeword.resources import get_embedding_model_path, get_mel_model_path

    sys.path.insert(0, str(VOICE_DIR))
    from mcfly_voice.wakeword import WakeWordDetector

    model = config.model_output_dir / f"{config.model_name}.onnx"
    data_dir = Path(tempfile.mkdtemp())
    (data_dir / "wakeword").mkdir()
    shutil.copy(get_mel_model_path(), data_dir / "wakeword" / "melspectrogram.onnx")
    shutil.copy(get_embedding_model_path(), data_dir / "wakeword" / "embedding_model.onnx")
    shutil.copy(model, data_dir / "wakeword" / model.name)
    ours = WakeWordDetector(config.model_name, data_dir=data_dir)
    theirs = WakeWordModel(models=[model])

    for split in ("positive_test", "negative_test"):
        a, b = [], []
        paths = sorted((config.model_output_dir / split).glob("clip_*_r0.wav"))
        for path in paths[::max(1, len(paths) // 1000)]:  # ~1,000 clips is plenty
            with wave.open(str(path)) as w:
                audio = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2")[-32000:]
            ours.reset()
            score = 0.0
            for i in range(0, len(audio) - 1279, 1280):
                score = ours.score(audio[i:i + 1280].tobytes())
            a.append(score)
            b.append(next(iter(theirs.predict(audio).values())))
        a, b = np.array(a), np.array(b)
        log.info("%s: %d clips, %.1f%% at or above 0.5 on the Pi's detector; "
                 "|Pi - trainer| mean %.3f, correlation %.3f", split, len(a),
                 100 * (a >= 0.5).mean(), np.abs(a - b).mean(), np.corrcoef(a, b)[0, 1])


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    config_path = sys.argv[1]
    config = load_config(config_path)
    stages = STAGES if sys.argv[2:] == ["all"] else sys.argv[2:]
    for stage in stages:
        start = time.monotonic()
        log.info("=== %s", stage)
        if stage == "setup":
            from livekit.wakeword.cli import setup
            setup(data_dir=config.data_dir, config_path=Path(config_path), skip_acav=False)
        elif stage == "generate":
            from livekit.wakeword.data.generate import run_generate
            shuffle_speaker_pairs()
            keep_pauses()
            weight_custom_negatives(config)
            run_generate(config)
        elif stage == "augment":
            from livekit.wakeword.data.augment import run_augment
            run_augment(config)
        elif stage == "extract":
            from livekit.wakeword.data.features import run_extraction
            run_extraction(config, session_options())
        elif stage == "train":
            from livekit.wakeword.training.trainer import run_train
            run_train(config)
        elif stage == "export":
            from livekit.wakeword.export.onnx import run_export
            run_export(config, quantize=False, format="onnx")
        elif stage == "eval":
            from livekit.wakeword.eval.evaluate import run_eval
            run_eval(config, config.model_output_dir / f"{config.model_name}.onnx")
        elif stage == "check":
            check(config)
        else:
            sys.exit(f"unknown stage {stage!r}; stages: {', '.join(STAGES)} or all")
        log.info("=== %s done in %.0f s", stage, time.monotonic() - start)


if __name__ == "__main__":
    main()
