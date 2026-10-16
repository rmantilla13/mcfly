"""Simulate mode: the full protocol with no audio hardware or models, driven
by commands typed (or piped) on stdin. For developing the display and for
tests.

    wake <words...>   the wake word, then <words> as the transcript
    button            push-to-talk with nothing said (empty transcript)
    silence           the wake word with nothing said (empty transcript)
    next <words...>   what the next `listen` from a client will hear
    follow <words...> what the next follow-up hears: a `listen` that comes
                      within 2 s of a reply being said, the way
                      the display asks for one. Without it a follow-up hears
                      nothing, so a conversation ends after one answer
    quit              stop the service
"""

from __future__ import annotations

import asyncio
import logging
import math
import sys
import threading
import time
from collections.abc import Callable, Sequence
from typing import TYPE_CHECKING, TextIO

from .wakeword import display_name

if TYPE_CHECKING:
    from .service import Session, VoiceService

log = logging.getLogger(__name__)

HELP = ("commands: wake <words...> | button | silence | next <words...> | "
        "follow <words...> | quit (clients can also send listen, speak, ...)")

# A client's `listen` this soon after speech ended is a follow-up.
FOLLOW_UP_WINDOW = 2.0

# A rise and fall, like a short phrase.
FAKE_LEVELS = (0.18, 0.46, 0.72, 0.58, 0.66, 0.31, 0.12)


class SimBackend:
    wakeword_available = True
    stt_available = True
    tts_available = True
    mic_name = "Simulated mic"
    voice = "af_heart"
    speed = 1.0
    wakeword_model = "hey_mcfly"

    def set_voice(self, voice: str | None, speed: float | None) -> None:
        if voice:
            self.voice = voice
        if speed is not None:
            self.speed = speed

    async def set_wakeword_model(self, model: str) -> str | None:
        self.wakeword_model = model
        self.wakeword_name = display_name(model)
        return None

    def __init__(
        self,
        wakeword_name: str = "Hey McFly",
        *,
        listen_text: str = "What's for dinner tonight?",
        levels: Sequence[float] = FAKE_LEVELS,
        level_step: float = 0.07,
        transcribe_time: float = 0.3,
        word_time: float = 0.05,
    ) -> None:
        self.wakeword_name = wakeword_name
        self.next_text = listen_text
        self.levels = tuple(levels)
        self.level_step = level_step
        self.transcribe_time = transcribe_time
        self.word_time = word_time
        self.spoken: list[str] = []
        self.follow_ups: list[str] = []
        self._service: VoiceService | None = None
        self._pending: str | None = None
        self._text = ""
        self._said_at = -math.inf

    async def start(self, service: VoiceService) -> None:
        self._service = service
        log.info("simulate mode: %s", HELP)

    async def close(self) -> None:
        pass

    def begin_capture(self) -> None:
        # A stdin command picked the words; a client's `listen` hears
        # next_text, or, right after a reply, the next queued follow-up.
        if self._pending is not None:
            self._text = self._pending
        elif time.monotonic() - self._said_at <= FOLLOW_UP_WINDOW:
            self._text = self.follow_ups.pop(0) if self.follow_ups else ""
        else:
            self._text = self.next_text
        self._pending = None

    def end_capture(self) -> None:
        pass

    async def capture(self, session: Session) -> str:
        text = self._text
        for value in self.levels:
            session.level(value)
            await asyncio.sleep(self.level_step)
        session.transcribing()
        await asyncio.sleep(self.transcribe_time)
        log.info("heard: %r", text)
        return text

    async def speak(self, text: str) -> None:
        words = len(text.split())
        log.info("speaking (%d words): %s", words, text)
        self.spoken.append(text)
        await asyncio.sleep(self.word_time * words)
        self._said_at = time.monotonic()  # said to the end (not cut short)

    # stdin

    def command(self, line: str) -> bool:
        """Run one stdin command. Returns False for `quit`."""
        parts = line.strip().split(maxsplit=1)
        if not parts:
            return True
        cmd = parts[0].lower()
        rest = parts[1] if len(parts) > 1 else ""
        if cmd in ("quit", "exit"):
            return False
        if cmd == "wake":
            self._trigger("wakeword", rest)
        elif cmd == "button":
            self._trigger("button", "")
        elif cmd == "silence":
            self._trigger("wakeword", "")
        elif cmd == "next":
            self.next_text = rest
            log.info("the next listen will hear: %r", rest)
        elif cmd == "follow":
            self.follow_ups.append(rest)
            log.info("a follow-up will hear: %r", rest)
        elif cmd == "help":
            log.info(HELP)
        else:
            log.warning("unknown command %r; %s", cmd, HELP)
        return True

    def _trigger(self, source: str, text: str) -> None:
        assert self._service is not None
        self._pending = text
        if not self._service.wake(source):
            self._pending = None
            reason = self._service.gate.blocked_by() if source == "wakeword" else None
            log.info("%s ignored (%s)", "wake word" if source == "wakeword" else "button",
                     reason or "already listening")


def read_lines(loop: asyncio.AbstractEventLoop, handle: Callable[[str | None], None],
               stream: TextIO = sys.stdin) -> threading.Thread:
    """Feed each line of `stream` to `handle` on the event loop; None at EOF.
    A daemon thread, so a blocked read never holds up shutdown."""

    def worker() -> None:
        try:
            for line in stream:
                loop.call_soon_threadsafe(handle, line)
            loop.call_soon_threadsafe(handle, None)
        except RuntimeError:
            pass  # the loop closed first

    thread = threading.Thread(target=worker, name="stdin", daemon=True)
    thread.start()
    return thread
