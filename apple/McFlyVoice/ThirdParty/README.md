# Third-party components

McFly's voice uses open-source work, all under the Apache License 2.0
(full text in `Kokoro-CoreML-LICENSE.txt`).

| Component | By | Where it is |
| --- | --- | --- |
| Kokoro-82M text-to-speech model and voices | hexgrad | Model files fetched by `scripts/fetch-kokoro.sh` into `Sources/McFlyVoice/Kokoro` |
| Core ML conversion and Swift pipeline ([kokoro-coreml](https://github.com/mattmireles/kokoro-coreml), commit a3f1ff2) | Matt Mireles | `Sources/KokoroPipeline` |
| English pronunciation (Misaki lexicon, BART fallback model, text normalization), ported from [FluidAudio](https://github.com/FluidInference/FluidAudio) v0.17.4 | FluidInference, via kokoro-coreml | `Sources/KokoroG2P`, and the `g2p` model files |

Changes made for Homestead:

- `Sources/KokoroPipeline/KokoroPipeline.swift`: the duration stage runs on the CPU. The GPU
  compile of that graph aborts on macOS 27 (`PipelineConstants.durationComputeUnits`). The
  caller can cap the duration model size, run the flexible generator at a fixed list of
  lengths, and close the generator under memory pressure, which keeps memory flat.
- `Sources/KokoroPipeline/KokoroSynthesisExecutor.swift` and `MLMultiArrayHelpers.swift`:
  speech longer than the largest bucket throws instead of being cut off, and zero-padding
  never drops real frames.
- `Sources/KokoroG2P/EnglishTextNormalizer.swift`: the NeMo normalization pass (a prebuilt
  binary) is removed. The built-in number rules always run, after Homestead's own
  `SpokenText`, and also read thousands separators, "%", fraction characters ("2½"),
  superscripts and subscripts.
- `Sources/KokoroG2P/EnglishPhonemizer.swift`: digits are spelled as numbers instead of
  going to the BART model.
- Download, manifest and hosting code from kokoro-coreml's `swift-tts` package isn't used.
  The app contains no networking code.

The sources and these notes come from Homestead (the same author), where the changes
above were made; McFly uses them unchanged apart from names.
