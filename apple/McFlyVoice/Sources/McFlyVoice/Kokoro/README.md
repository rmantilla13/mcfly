# Kokoro voice files

McFly's voice: Kokoro-82M converted to Core ML, about 190 MB, the same files Homestead
bundles. They aren't in git. Fetch them once per checkout before building:

    apple/McFlyVoice/scripts/fetch-kokoro.sh

They come from huggingface.co/mattmireles/kokoro-coreml at a pinned revision and are
checked against the hashes in `scripts/kokoro-files.txt` (`--from <folder>` copies them
from another checkout instead, still checked). Kokoro-82M is by hexgrad, the Core ML
conversion by Matt Mireles, and the pronunciation models by FluidInference, all
Apache-2.0. Without these files the app still builds and speaks with the system voice;
`scripts/release-ios.sh` refuses to make a TestFlight build without them.
