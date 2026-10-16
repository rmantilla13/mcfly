# mcfly-voice

The McFly voice service. It runs on the Pi next to the display, listens for
the wake word on a USB mic, transcribes what you say on the device, and speaks
the reply. Say the wake word and the McFly display opens its quick-answer
card, sends what you said to the McFly `assistant` function (`quick` mode),
and asks this service to read the answer out. The display talks to it over a
local WebSocket (`ws://127.0.0.1:8765`); audio never leaves the Pi.

Hardware, privacy, tuning, wake-word training and troubleshooting are in
[docs/VOICE.md](../docs/VOICE.md), which also details the protocol; section 5
of [docs/PLATFORM_SPEC.md](../docs/PLATFORM_SPEC.md) is where it sits in the
platform.

```bash
pip install -e 'voice[dev]'                 # core + tests: needs only websockets
pytest voice
python -m mcfly_voice --simulate            # no mic or models; type `wake how are the markets`
./voice/deploy/install-voice.sh             # on the Pi: everything, as a systemd service
```

On the Pi it runs as the `mcfly-voice` systemd unit from `/opt/mcfly-voice`,
reads `/etc/mcfly/voice.toml` (every key documented in `voice.example.toml`)
and keeps its models in `~/.local/share/mcfly-voice`.

## The wake word

The default is "Hey McFly" (`hey_mcfly`), McFly's own model, trained for it
and shipped in `mcfly_voice/wakewords/`. The web console's display settings
switch between it and openWakeWord's built-ins (`hey_jarvis`, `alexa`,
`hey_mycroft`, `hey_rhasspy`) while the service runs. To start with another
one, or with a `.onnx` file of your own, set `wakeword.model` in
`/etc/mcfly/voice.toml`, fetch it, and restart:

```toml
[wakeword]
model = "hey_mycroft"      # one of those, or "my_phrase.onnx" from ~/.local/share/mcfly-voice/wakeword
name = ""                  # what the display shows; empty derives it ("Hey Mycroft")
```

```bash
/opt/mcfly-voice/bin/python -m mcfly_voice --download-models
sudo systemctl restart mcfly-voice
```

Retraining "Hey McFly", or training another phrase, takes about an hour on a
Mac with no recordings needed; docs/VOICE.md walks through it, along with
tuning `wakeword.threshold` for your room.

| Module | Job |
|---|---|
| `service.py` | WebSocket server, session state machine, wake-word suppression |
| `protocol.py` | Message shapes and client message checks |
| `pipeline.py` | Real backend: mic → wake word → end of speech → Whisper; TTS → speaker |
| `simulate.py` | Simulate backend, driven by stdin |
| `audio.py`, `vad.py`, `wakeword.py`, `stt.py`, `tts.py` | sounddevice/aplay, webrtcvad + energy, openWakeWord, faster-whisper, Kokoro (Homestead's voice) + Piper + espeak-ng |
| `config.py` | TOML settings (`voice.example.toml` documents every key) |
