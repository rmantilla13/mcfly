# Voice

Say "Hey McFly", ask a question, and the display answers out loud, then
listens for a follow-up, so you can keep talking without saying the wake
word again. The voice service (`voice/`, the Python package `mcfly_voice`)
runs on the Pi next to the display. It listens for the wake word, records
what you say, turns it into text, and speaks the reply. The display does
everything else: it shows the voice card, sends the text to the assistant,
asks the service to speak the answer, and opens the mic again for the next
question.

```
 USB mic ──▶ wake word ──▶ end of speech ──▶ Whisper ──┐ transcript   ┌──────────────┐  text  ┌───────────┐
            (openWakeWord)   (webrtcvad)     (on CPU)  ├─────────────▶│   display    │───────▶│ assistant │
                                                       │  WebSocket   │ (VoiceClient)│◀───────│ (Claude)  │
 speakers ◀── aplay ◀── Kokoro / Piper / espeak-ng ◀───┘◀─────────────│              │ reply  └───────────┘
                                                          speak       └──────────────┘
```

Audio never leaves the device. Only the transcribed text does, and the
display is what sends it, to the `assistant` function in `quick` mode.

## Hardware

**A USB microphone is required.** The JUNEBOX 10.1" panel has speakers (its
audio arrives over HDMI) but no microphone, and the Pi 5 has no audio input
of its own.

Any USB microphone that works without a driver (a "USB Audio Class" device,
which is nearly all of them) works: if `arecord -l` lists it, the service can
use it. It records whatever rate and channel count the mic offers and
converts.

| Mic | Notes |
|---|---|
| A USB conference or "boundary" mic | The simplest choice: omnidirectional, picks people up across a kitchen. Prefer a mic-only one: a speakerphone also shows up as a speaker, and PipeWire may play replies on it instead of the panel |
| ReSpeaker USB Mic Array (XMOS) | Better in a noisy room. If it only records multi-channel, set `audio.input_channel` |
| A cheap USB lavalier or dongle mic | Works within a couple of metres; raise its gain in `alsamixer` |

- Put the mic where people face the screen, away from the panel's speakers
  and from fans, dishwashers and range hoods.
- Plug it in before or after starting; the service looks for a mic every 10
  seconds. With no setting it picks the first USB microphone.
- If the mic goes quiet without being unplugged, the service closes it and
  opens it again: listening is back a few seconds after the last audio
  (see [When the mic goes quiet](#when-the-mic-goes-quiet)).
- To see which mic it found, tap the gear: **About → Microphone** shows the
  mic's name, or **Not found** in red when the service is running without
  one.
- Replies play through the panel's speakers. With the display user's
  PipeWire session up (the display installer starts it at boot), that is the
  same output the gear menu calls **Screen speakers**: off stays silent, and
  **Volume** is how loud a reply is. The service does not open HDMI on its
  own in that case, so a reply cannot keep the panel hissing. Without
  PipeWire it falls back to ALSA card `vc4hdmi0` (HDMI0, next to USB-C
  power), even if a USB mic took card 0 at boot. To play anywhere else
  (HDMI1, a USB speaker), set `audio.output_device`.

### When the mic goes quiet

The service reads the mic through PortAudio in 80 ms blocks, from the USB
device itself (`hw:N,0`). Left to choose, PortAudio gave it a buffer of two
blocks, and the Pi 5 wakes the reader only about every second block: the
buffer overflowed about once a second, and PortAudio restarted the capture
each time. Now and then the mic (a C-Media "USB PnP Sound Device") stayed
silent after a restart, without going away. Closing it then waited for
PortAudio's reader to give up on the silent device, 2048 empty polls of 80 ms
each, so every stall took 2 minutes 47 seconds. The whole service waited
with it, the display's connection included.

Each overflow also threw away about 170 ms of whatever was being said.
Commands played through the panel and recorded with that two-block buffer
were missing a sixth of their audio, mostly from the middle, and Whisper got
19–36% of their words wrong ("add cup dry cleaning my to dust"). Recorded
with room to spare, nothing was lost and `base.en` got them all right, as it
does the clean audio. A bigger model can't bring back what was never
recorded: `small.en` was as wrong on the broken audio, and four times slower.

Now:

- The buffer holds four blocks (320 ms), so the reader has time to spare.
- When audio is lost anyway, the log says `microphone: input overflowed N
  times; audio was lost`, at most once a minute.
- A mic that stops sending audio (`the microphone stopped sending audio;
  reopening it`) is aborted rather than stopped, on a worker thread, and
  opened again half a second later.
- A mic that opens but never sends anything is tried again every 10 seconds,
  with one warning: `the microphone sent no audio`.

With the service running, the kernel shows whether the capture is still being
restarted (use the mic's card number from `arecord -l`):

```bash
cat /proc/asound/card0/pcm0c/sub0/hw_params   # buffer_size is 4 × period_size
grep trigger /proc/asound/card0/pcm0c/sub0/status   # changes at every restart
```

## Install

On the Pi (64-bit Raspberry Pi OS; Lite is fine), from the repository:

```bash
./voice/deploy/install-voice.sh             # or: ./display/deploy/install-pi.sh --with-voice
```

The script:

- installs `python3-venv libportaudio2 espeak-ng alsa-utils`
- creates a virtualenv at `/opt/mcfly-voice` and installs the package with
  the `audio`, `stt`, `tts` and `wake` extras. Every dependency comes as a
  prebuilt wheel for the Pi's Python (3.13 on Raspberry Pi OS Trixie), about
  180 MB, so nothing is compiled and it takes a few minutes. openWakeWord is
  installed without its `tflite-runtime` dependency, which doesn't exist for
  Python 3.12 and later; the service runs its ONNX models instead.
- writes `/etc/mcfly/voice.toml` from `voice/voice.example.toml` (kept on
  re-runs)
- downloads the models once (about 340 MB) into `~/.local/share/mcfly-voice`:
  Kokoro-82M, the voice Homestead speaks with (the int8 model and its voices,
  from [kokoro-onnx's release](https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0),
  checked against pinned SHA-256s), the Piper voice it falls back to, and the
  Whisper model from Hugging Face
  ([rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices),
  [Systran/faster-whisper-base.en](https://huggingface.co/Systran/faster-whisper-base.en)),
  and openWakeWord's feature models and built-in wake words from its
  [GitHub release v0.5.1](https://github.com/dscripka/openWakeWord/releases/tag/v0.5.1).
  The "Hey McFly" wake word comes with the package; it is copied into
  `~/.local/share/mcfly-voice/wakeword`, replacing an older copy
- installs and starts the `mcfly-voice` service, as the same user as the
  display, and enables it for every boot. It waits a few seconds at startup
  for that user's PipeWire socket, then listens whether or not a microphone
  is plugged in yet

Re-run it to update. Add `--skip-models` to install without downloading
models; fetch them later with
`/opt/mcfly-voice/bin/python -m mcfly_voice --download-models`.

### Check the mic and the speakers

Once, after installing. Stop the service so the tests can open the devices:

```bash
sudo systemctl stop mcfly-voice
arecord -l                       # the USB mic is a "card N: ... USB Audio" line
arecord -D plughw:N,0 -f S16_LE -r 16000 -c 1 -d 5 /tmp/t.wav   # N from arecord -l; talk for 5 s
aplay -D default:CARD=vc4hdmi0 /tmp/t.wav                     # plays it on the panel
/opt/mcfly-voice/bin/python -m mcfly_voice --say "Hello from McFly"
sudo systemctl start mcfly-voice
```

Play the panel through `default:CARD=vc4hdmi0` (or `plughw:CARD=vc4hdmi0`),
never `hw:`: the Pi's HDMI audio only takes IEC958 frames, which the `default`
and `plughw` devices convert to. `--say` speaks through exactly what the
service uses, so if it's heard, replies will be too.

| Task | Command |
|---|---|
| Watch logs | `journalctl -u mcfly-voice -f` |
| Restart | `sudo systemctl restart mcfly-voice` |
| Change settings | `sudo nano /etc/mcfly/voice.toml`, then restart |
| Test the voice | `/opt/mcfly-voice/bin/python -m mcfly_voice --say "Hello from McFly"` |
| List audio devices | `/opt/mcfly-voice/bin/python -m mcfly_voice --list-devices` |

The display finds the service at `ws://127.0.0.1:8765` (override with
`MCFLY_VOICE_URL` in `/etc/mcfly/display.env`) and reconnects every 5
seconds, so the two can start in any order.

## Privacy

- **Nothing is recorded or stored.** Audio exists only in memory: a rolling
  window of the last few seconds for the wake-word model (openWakeWord keeps
  up to 10 s), and one question while it's transcribed, which is dropped
  right after. No audio is written to disk.
- **No audio leaves the Pi.** Wake word, speech to text and text to speech
  all run on the Pi's CPU. The transcribed text goes to the display, which
  sends it to the assistant, like a typed question.
- **The service makes no network requests.** Models are downloaded only by
  `--download-models` (run by the install script); the systemd unit sets
  `HF_HUB_OFFLINE=1` so nothing is fetched while it runs, and its
  `IPAddressDeny=any` / `IPAddressAllow=localhost` firewall holds it to the
  display's localhost socket. The unit also sandboxes it (read-only system
  directories, no new privileges).
- **Turning the wake word off sticks.** The switch in the display's settings
  sheet is saved in `~/.local/share/mcfly-voice/state.json` and survives
  restarts. With it off, the mic is opened but nothing is analysed until
  someone taps the mic button.
- **Follow-ups listen briefly, and only mid-conversation.** After McFly reads
  an answer out, it listens for up to 4 s for a follow-up (longer only while
  someone keeps talking), the same way as after the wake word, and only in a
  conversation someone started with the wake word or a tap. Settings →
  Voice → **Follow-up questions** turns that off.
- **Logs don't contain what was said** at the default `info` level, only
  timings. `debug` logs include transcripts; don't leave it on.
- The WebSocket listens on localhost only and has no authentication. Don't
  set `server.host` to `0.0.0.0` on a shared network.
- **Web pages can't use it.** A site open in a browser on the Pi could
  otherwise reach `ws://127.0.0.1:8765`, switch the mic on and read what was
  said. Browsers always send an `Origin` header and the display doesn't, so
  any connection with one is refused (HTTP 403) unless it's listed in
  `server.allowed_origins` (empty by default).
- For a hard guarantee, unplug the USB mic, or use one with a mute switch.

## How a question flows

1. The wake word is heard (or someone taps the mic button: push-to-talk).
   The service sends `wake` and switches to `listening`.
2. While listening it sends the mic `level` up to 15 times a second; the
   display's orb pulses with it.
3. The question ends after 0.7 s of silence, 8 s of speech at most, or 4 s
   with nobody speaking at all. Then `transcribing`, then the `transcript`.
   An empty transcript means nothing was heard.
4. The display asks the assistant and sends `speak` with the reply. The
   service speaks it and answers `spoken`.
5. 0.7 s after `spoken` (once the room's echo has faded), the display sends
   `listen` itself: a follow-up, no wake word needed, with the earlier turns
   sent along as history. Say nothing for 4 s, or just "thanks", "that's
   all", "never mind" or "bye", and the conversation ends; the display also
   ignores a follow-up that repeats the end of the answer (McFly hearing
   itself) and stops after six answers. Tapping the card while McFly is
   talking cuts it short and listens; tapping it after an answer asks
   another question. The card waits for `spoken` however long the answer
   takes to say, as long as the service still reports `speaking` (Kokoro is
   slower than real time on the Pi). The display's log says why each
   conversation went on or ended, never what was said:
   `journalctl -u mcfly-display | grep "voice card"`.

Every question asked out loud gets a spoken answer: the wake word, the mic
on Home (which opens the same voice card) and the mic in the assistant
panel (which asks for the same short, spoken answer, and shows it in the
chat). Typed questions are answered in the chat only. Two switches in the
display's settings sheet (gear → Settings → Voice) govern this: **Spoken
replies** (off: answers only appear on screen, and nothing follows up) and
**Follow-up questions** (off: one question, one answer, and the card closes
6 s after it). The second is the display's own choice and isn't synced to
the console or the other devices.

Ask it to add to your day ("put the dentist on Friday at 3", "remind me to
call mom at 5", "add milk to my list", "I bought the milk") and the
assistant does, with its tools ([PLATFORM_SPEC.md](PLATFORM_SPEC.md) §2.4),
then says what it saved. When a reminder's time comes, the display shows it
at the top of the screen and sends `speak` with it, once.

The wake word is ignored while the service is speaking (so it can't wake
itself), while a question is in progress, for 2 s after it fires, and for
0.5 s after speaking or listening ends, while the room's echo fades.

## One voice everywhere

McFly speaks with the same Kokoro voice on the Pi, in the web console and on
the iPhone and Mac: Heart unless someone picks Bella, Michael or Fenrir. It is
one choice for the account, and picking it anywhere changes it everywhere.

| Picked on | Goes to | The others follow |
|---|---|---|
| The display (gear → Settings) | The voice service, then its own `devices.settings.voice` (`device_update_settings`) | The web and the app read it from `admin_list_devices` |
| The console (Displays → Customize) | That display, then every other one (`admin_update_device_settings`) | The display within a minute (its sync), the web and the app likewise |
| The web (`/voice`) or the app (Settings → Voice) | Every display (`admin_update_device_settings`, `{ "voice": … }` alone) | The display within a minute; the web and the app likewise |

- **Where it lives.** The displays' settings (`devices.settings.voice`) hold
  it; no table of its own. The account's voice is the first display's (oldest
  first, as `admin_list_devices` orders them) that has one. With no display
  paired there is nowhere to share it, so the web and the app each keep their
  own choice until one is.
- **When the others catch up.** The display syncs every minute. The web's
  voice page rereads it every minute and whenever the tab is looked at again;
  Ask and the Today panel do while they read replies aloud. The app rereads
  it when it comes to the front, when Settings opens and while McFly thinks
  about each spoken question, so an answer is read in the voice picked
  elsewhere a moment ago.
- **This device's voice stays put.** The web and the app also offer the
  browser's or the system's own voice. That choice is the device's alone
  (`mcfly.voice` in the browser's storage or the app's defaults), is never
  sent, and a voice picked elsewhere doesn't override it. Picking a Kokoro
  voice again rejoins the account's.
- **The voice service coming back.** It remembers its voice across restarts
  (`state.json`), so its first `hello` after it reconnects says what it ran
  before, not a choice. If the account's voice changed meanwhile, the display
  sends that one to the service rather than the old one to the server
  (`SettingsBridge`).
- **More than one display.** A pick on the web, in the app or in Customize
  goes to all of them. One made on a display's own screen reaches only that
  display's row: the web and the app follow it only if it's the oldest
  display with a voice, and the other displays don't follow it. With one
  display, as today, that doesn't arise.

## Settings and tuning

Every key is optional; `voice/voice.example.toml` lists them all with their
defaults. The ones you're most likely to touch:

| Setting | Default | When to change it |
|---|---|---|
| `wakeword.threshold` | `0.5` | Raise (0.6–0.7) if it wakes on TV chatter; lower (0.3–0.4) if it misses you |
| `wakeword.model` / `name` | `hey_mcfly` | To start with another wake word: `hey_jarvis`, `alexa`, `hey_mycroft`, `hey_rhasspy` or a `.onnx` of your own. The display's settings sheet and the web console's display settings switch between the named ones while it runs, and that choice wins over this setting |
| `vad.silence` | `0.7` s | Raise to 1.0 if it cuts people off mid-sentence |
| `vad.aggressiveness` | `2` | 3 in a noisy kitchen (stricter about what counts as speech) |
| `vad.no_speech` | `4.0` s | How long it waits for you to start after the wake word |
| `stt.model` | `base.en` | `tiny.en` is faster but sloppier; `small.en` is more accurate but noticeably slower on a Pi |
| `stt.initial_prompt` | empty | Names and odd words, e.g. `"McFly, Grok, NVDA, Daily Pulse."` |
| `tts.engine` | `auto` | `kokoro`, `piper`, `espeak` or `off`; `auto` tries them in that order |
| `tts.kokoro_voice` | `af_heart` | Homestead's voices: `af_heart` (Heart), `af_bella` (Bella), `am_michael` (Michael), `am_fenrir` (Fenrir). What the service starts with before anything has picked one; once the display has synced, the account's voice (One voice everywhere, above) wins, and the display, the web and the app change it while running |
| `tts.voice` | `en_US-amy-medium` | The Piper fallback: any [Piper voice](https://rhasspy.github.io/piper-samples/), then `--download-models` |
| `tts.speed` | `1.0` | `1.1`–`1.2` for snappier answers |
| `audio.input_device` / `output_device` | auto | When it picks the wrong mic or speaker |

**Tuning the wake word.** Run with `log_level = "debug"` for a while and
watch `journalctl -u mcfly-voice -f`. Every near miss is logged as
`wake word score 0.31 (threshold 0.50)`. If you see real attempts scoring
0.3–0.5, lower the threshold; if false wakes score just above it, raise it.
Turn debug off again afterwards (it logs transcripts).

**Changing models.** After changing `stt.model`, `tts.voice` or
`wakeword.model`, fetch them, then restart:

```bash
/opt/mcfly-voice/bin/python -m mcfly_voice --download-models
sudo systemctl restart mcfly-voice
```

If webrtcvad isn't installed, end-of-speech falls back to a loudness
detector (`vad.engine = "energy"`, tuned by `vad.energy_threshold`). It
works in a quiet room but treats any steady sound as speech for a moment.

## The "Hey McFly" wake word

"Hey McFly" (`hey_mcfly`) is McFly's own wake word and the default. It is an
openWakeWord model like the built-in ones and runs on the same feature
models, but it ships inside the package (`voice/mcfly_voice/wakewords/`,
under 1 MB) instead of being downloaded: `--download-models` copies it into
`~/.local/share/mcfly-voice/wakeword`, replacing an older copy, and the
service falls back to the package's copy when that folder doesn't have one.
The display's settings sheet (gear → Settings) and the web console's display
settings (Displays → Customize) switch a display between it and the built-ins.

It was trained from synthetic speech, with no recordings, using
[livekit-wakeword](https://github.com/livekit/livekit-wakeword) 0.3.0 on a
Mac's GPU, through `voice/training/train.py` with the settings in
`voice/training/hey_mcfly.yaml`:

- 33,600 clips of "hey mcfly" (and "hey mick fly"), in voices blended from
  904 LibriTTS speakers at five speaking rates; in 30% of them the voice
  pauses after "hey", as people do
- 40,800 near misses that must not wake it: about 8,000 generated
  sound-alikes, and a fifth of the clips from named ones such as "McFly"
  alone, "Marty McFly", "hey Mickey", "hey Siri", "hey Jarvis", "hey, fly"
  and "make it fly"
- room echo (MIT impulse responses) and background noise (MUSAN) mixed in
- 2,000 hours of general audio (ACAV100M features) as examples of what isn't
  the wake word

The shipped model came from three rounds (the pauses and the named near
misses were added as gaps showed up); a fresh run of the YAML gives a
comparable model, not an identical one.

How it did, scored by McFly's own detector at the default threshold (0.5):

| Test | Result |
|---|---|
| Held-out synthetic "Hey McFly", with noise and echo | 91% caught; 61% when there's a pause after "hey" |
| 21 macOS voices it never trained on (as "hey Mick Fly": macOS reads "Mc" as the letters M C) | 62 of 63 caught; 35 of 63 with a pause |
| openWakeWord's validation set, ~11 h of general audio | A few false wakes, about as many as "Hey Jarvis" (the trainer also tunes against this set, so it's not held out) |
| 26 near-miss phrases, not in training, in 21 voices | Fires on close sound-alikes ("hey flies", "hey Clyde", "hey McCoy"): 76 of 546 clips; 1 of 189 everyday "hey, ..." lines |

Say it in one breath for the surest wake; with a pause after "hey" it wakes
a little over half the time. Real rooms differ: if it wakes on the TV or on
sound-alikes, set `wakeword.threshold = 0.6` (in these tests that cut its
firing on sound-alikes by a sixth and cost about 1 point of recall, 4 with a
pause); if it misses you, try 0.4.

**Retraining** it, or training another phrase, takes about three hours and
19 GB of downloads on an Apple-silicon Mac (it needs `espeak-ng`, from
Homebrew):

```bash
repo=$(pwd)                                    # the McFly checkout
mkdir -p ~/wake-train && cd ~/wake-train       # data and output land here (~25 GB)
uv venv --python 3.12 && source .venv/bin/activate
uv pip install 'livekit-wakeword[train,eval,export]==0.3.0'
uv pip install --no-deps 'openwakeword>=0.6,<0.7'
python "$repo/voice/training/train.py" "$repo/voice/training/hey_mcfly.yaml" all
cp output/hey_mcfly/hey_mcfly.onnx "$repo/voice/mcfly_voice/wakewords/"
```

Its last stage, `check`, scores held-out clips through McFly's own
detector, the way the Pi will. For another phrase, copy the YAML and change
`model_name`, `target_phrases` (spelled the way it's said, since the clips
come from text to speech) and the near misses, then set `wakeword.model` to
the new `.onnx` file. A retrained `hey_mcfly.onnx`, once committed, reaches
a Pi with `git pull` and `./voice/deploy/install-voice.sh`, which copies it
over the old one.

## Protocol

JSON text frames on `ws://127.0.0.1:8765`. Section 4 of
[PLATFORM_SPEC.md](PLATFORM_SPEC.md) is the contract; these are the details
behind it.

| Server → client | When |
|---|---|
| `{"type":"hello","version":"1","wakeword":bool,"wakeword_name":str,"wakeword_model":str,"tts":bool,"stt":bool,"mic":str,"voice":str,"speed":num}` | On connect, and again to everyone after `set` or when the mic is plugged in or unplugged |
| `{"type":"state","state":"idle\|listening\|transcribing\|speaking"}` | On connect (right after `hello`) and on every change |
| `{"type":"wake","source":"wakeword\|button"}` | A session starts; always followed by `listening` |
| `{"type":"level","rms":0.0-1.0}` | While listening, at most 15/s |
| `{"type":"transcript","text":str,"final":true}` | Once per session, unless it was cancelled; `""` if nothing was heard |
| `{"type":"spoken","id":str}` | Exactly once per `speak`, when finished, stopped or skipped |
| `{"type":"error","message":str}` | Bad client message (to that client only), or a runtime problem |

| Client → server | Effect |
|---|---|
| `{"type":"listen"}` | Push-to-talk. Interrupts speech; ignored if a session is already running |
| `{"type":"cancel"}` | Ends the session without a transcript, stops speech, and goes `idle` |
| `{"type":"speak","text":str,"id":str}` | Queues speech. Waits for a session in progress to finish. `id` is optional (one is made up) and at most 200 characters. Text past 2,000 characters is cut at a word break. With 16 replies already waiting, it's refused with an `error` and an immediate `spoken` |
| `{"type":"stop_speaking"}` | Stops speech and drops anything queued; each pending id gets `spoken` |
| `{"type":"set","wakeword_enabled":bool}` | Switches the wake word on or off; answered with a fresh `hello` to every client |
| `{"type":"set","wakeword_model":str,"voice":str,"speed":num}` | Any of them: the wake word (`hey_mcfly`, `hey_jarvis`, `alexa`, `hey_mycroft` or `hey_rhasspy`), Kokoro's voice (`af_heart`, `af_bella`, `am_michael`, `am_fenrir`) and the speaking rate (0.5–2). Remembered across restarts; answered with a fresh `hello` to every client, or an `error` if the wake word can't load |

- A frame over 64 KiB closes the connection (code 1009); a handshake with
  an `Origin` header not in `server.allowed_origins` is refused with 403.
- `level` is the frame's loudness mapped from −60…0 dBFS onto 0…1, so normal
  speech reads about 0.4–0.8 and can drive the orb directly.
- In `hello`, `wakeword_model` is the wake word in use (`hey_mcfly`) and
  `wakeword_name` what the display shows ("Hey McFly"); `mic` is the open
  microphone's name (`""` when there's none), `voice` Kokoro's voice (`""`
  when another engine speaks) and `speed` the speaking rate. Clients ignore
  keys they don't know.
- `hello.wakeword` is true only when the wake word is switched on *and*
  working: the mic, the wake-word model and the Whisper model are all there.
  `stt` is false without a mic or the Whisper model; `listen` is then
  answered with an `error`. `tts` is false without Piper or espeak-ng;
  `speak` then gets an `error` and an immediate `spoken`.
- Speech is markdown- and emoji-stripped before it's spoken; list items are
  read as short sentences.

## Development

```bash
pip install -e 'voice[dev]'
pytest voice
python -m mcfly_voice --simulate           # add --port 0 for any free port
```

For the real models on a development machine, `pip install -e 'voice[all,dev]'`.
On Python 3.12 and later, add openWakeWord on its own, as the install script
does: `pip install --no-deps 'openwakeword>=0.6,<0.7'`.

Simulate mode needs no audio hardware or models. It speaks the full
protocol, and you drive it by typing on stdin:

| Command | Does |
|---|---|
| `wake what's for dinner` | The wake word, then a fake session that hears "what's for dinner" |
| `button` / `silence` | A session that hears nothing (empty transcript) |
| `next turn off the lights` | What the next push-to-talk `listen` hears (default "What's for dinner tonight?") |
| `follow and tomorrow?` | What the next follow-up hears: a `listen` within 2 s of a reply being said, the way the display asks for one. Without it a follow-up hears nothing, so the conversation ends after one answer |
| `quit` | Stop |

`speak` requests are logged and answered with `spoken` after 0.05 s per
word. The simulator check for the display: run the display in demo mode,
start `python -m mcfly_voice --simulate`, type `wake what's for dinner` once
the display has connected, and watch the quick-answer card. To script it,
delay the commands so the display is connected first:

```bash
(sleep 8; echo "wake what's for dinner"; cat) | python -m mcfly_voice --simulate
```

Closing stdin doesn't stop the service; Ctrl+C or `quit` does.

## Troubleshooting

Stop the service first (`sudo systemctl stop mcfly-voice`) so the tests below
can open the devices, and start it again afterwards.

| Symptom | Check |
|---|---|
| `no microphone found` in the log | `arecord -l` should list a USB card. If it doesn't, try another USB port or cable; `dmesg -w` shows it being plugged in |
| It hears nothing / the orb barely moves | Record 5 s and play it back: `arecord -D plughw:2,0 -f S16_LE -r 16000 -c 1 -d 5 /tmp/t.wav && aplay -D default:CARD=vc4hdmi0 /tmp/t.wav` (use the card number from `arecord -l`). If it's quiet, raise the capture gain: `alsamixer -c 2`, F4 |
| It picks the wrong mic | `/opt/mcfly-voice/bin/python -m mcfly_voice --list-devices`, then set `audio.input_device` to part of the name, e.g. `"USB"` or `"ReSpeaker"` |
| `the microphone stopped sending audio; reopening it` in the log | The mic went quiet and was reopened ([When the mic goes quiet](#when-the-mic-goes-quiet)). Now and then is fine. If it comes every few minutes, look for `input overflowed` lines too, check `vcgencmd get_throttled` (a hot or underpowered Pi) and try another USB port |
| `microphone: input overflowed … audio was lost` | The service read the mic too late and lost audio, which can cost a wake word. A few a day are harmless; one a minute means the Pi is too busy (or too hot) to keep up |
| `the microphone sent no audio` | The mic opens but records nothing. Unplug it and plug it back in, or try another port; the `arecord` test above shows whether it records at all |
| Replies are silent | In the gear menu, **Screen speakers** off means replies stay quiet on purpose. Turn them on and raise **Volume**, and check the panel's own buttons. Then try `--say` (above). `aplay -l` lists outputs; the panel is `vc4hdmi0` on HDMI0 and `vc4hdmi1` on HDMI1. Test it: `speaker-test -D default:CARD=vc4hdmi0 -c 2 -t wav -l 1`. On HDMI1, set `audio.output_device = "default:CARD=vc4hdmi1"`. `wpctl status` shows the PipeWire output the service uses (see [PI_SETUP.md](PI_SETUP.md)) |
| `aplay: ... Device or resource busy` | Something else is playing through the same card. `fuser -v /dev/snd/*` shows what; stop it or pick another output |
| Wakes by itself | Raise `wakeword.threshold`; move the mic away from the speakers and the TV |
| Never wakes | Check the log for `wake word unavailable` (model missing: run `--download-models`). Then lower the threshold, and check that the display's wake word switch is on |
| Cuts you off | Raise `vad.silence` to 1.0 |
| Waits long after you stop talking | Background noise reads as speech: try `vad.aggressiveness = 3`, or move the mic |
| Wrong words | First look for `input overflowed` in the log: lost audio drops whole syllables, and no model gets them back. Then add names to `stt.initial_prompt`, speak closer to the mic, or try `stt.model = "small.en"` (about four times slower on the Pi) |
| Slow to answer | The log times each step: `transcribed N s of audio in N s` (Whisper), `reply to speak arrived N s after the transcript` (the display asking the assistant), `speaking N characters (kokoro): first audio after N s` (the voice). On a hot Pi Whisper and Kokoro each take seconds; see the next row |
| Not Homestead's voice | Kokoro isn't loading, so it fell back to Piper (or espeak-ng). The log says why; usually the models need `--download-models` |
| Answers start late, or pause between sentences | Kokoro renders a reply piece by piece (`speech_pieces`), the next while the last plays. The first piece is a short sentence or clause, so speaking starts soon; the rest flows only while Kokoro renders faster than it speaks. A hot Pi slows to 1–1.5 GHz and falls behind: at 1 GHz the first words came 2–6.5 s after the reply (9–17 s when the first piece was the whole answer), then the rest paused 6–12 s while it rendered. `vcgencmd measure_temp` and `vcgencmd get_throttled` show it; fit the Active Cooler ([PI_SETUP.md](PI_SETUP.md)) |
| Robotic voice | Neither Kokoro nor Piper loaded, so it fell back to espeak-ng. The log says why |
| `GPU device discovery failed ... /sys/class/drm/...vendor` in the log | Harmless: onnxruntime looks for a GPU it could use, and the Pi's doesn't describe itself that way. Ignore it |
| Display says "Voice needs the McFly voice service" | `systemctl status mcfly-voice`; the service listens on `127.0.0.1:8765` |
