# FieldTalk Android workspace instructions

- [x] Clarify project requirements — native Kotlin/Compose, offline medical speech translation, English/Chinese/Russian.
- [x] Scaffold the Android project.
- [x] Implement the translator workflow and local inference boundaries.
- [x] Integrate Android on-device ASR, local translation, and offline-only Android TTS.
- [x] Compile and test the project.
- [x] Add VS Code build task.
- [x] Document model preparation, safety, privacy, and launch steps.

## Engineering rules

- Do not add the Android `INTERNET` permission; production inference must stay on-device.
- Do not claim models or inference are ready unless all required assets pass manifest and checksum validation.
- Never log transcript, translation, recorded audio, or other medical content.
- Keep ASR, translation, and TTS behind interfaces so model runtimes can be upgraded independently.
- Supported pairs are English↔Simplified Chinese and English↔Russian only.
- Treat output as an unvalidated communication aid, not medical advice or diagnosis.
- Store generated audio and recordings only in app-private cache and remove them after use.
- Prefer Kotlin, coroutines, immutable UI state, Compose Material 3, and unit-testable services.
