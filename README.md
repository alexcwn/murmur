# Murmur

Push-to-talk dictation for macOS. Hold a key, speak, release — cleaned-up text
lands at your cursor in whatever app is focused.

A Wispr Flow clone, built fully on-device: Apple's `SpeechAnalyzer` for
transcription and Foundation Models for cleanup. Nothing leaves the machine.

> **Name is a placeholder.** Branding pass comes later; `Murmur` appears in
> `Package.swift`, `Resources/Info.plist`, `Makefile` and the bundle ID
> `com.alexchoo.murmur`.

## Requirements

- macOS 26+ (both `SpeechAnalyzer` and `FoundationModels` are 26-only)
- Apple Silicon
- Command Line Tools (Xcode not required yet)

## Setup

```bash
make cert     # once — creates a stable signing identity, asks for your password
make run      # build, bundle, sign, launch
```

The menu bar icon *is* the status display — there is no window:

| Icon | Meaning |
|---|---|
| ⚠ warning triangle | Permissions needed — expected on first run |
| mic | Ready; hold your hotkey to dictate |
| filled mic | Listening |
| ⋯ | Transcribing / cleaning up |

**On first run you are looking for a warning triangle, not a mic.** Click it →
Settings… and grant these three:

| Permission | Why |
|---|---|
| Microphone | Hear you while the key is held |
| Accessibility | Insert text at your cursor in other apps |
| Input Monitoring | Detect the push-to-talk key globally |

If you use the default **Fn** hotkey, also set System Settings → Keyboard →
"Press 🌐 key to" → **Do Nothing**, or the globe key opens the emoji picker at
the same time.

## Why `make cert` matters

macOS ties TCC permission grants to bundle ID **and code signature hash**.
Ad-hoc signing produces a new hash every build, so every rebuild silently drops
your Accessibility and Input Monitoring grants. One stable self-signed identity
means you approve once.

## Architecture

```
Fn down ──> HotkeyMonitor      CGEventTap, listen-only, modifier-hold
                │
                ├─> AudioCapture       AVAudioEngine, pre-warmed at launch
                │        │ streams AnalyzerInput while held
                │        ▼
                ├─> TranscriptionEngine  «protocol»
                │      └─ AppleSpeechEngine    SpeechAnalyzer, on-device
                │
Fn up ─────────>│
                ├─> TextFormatter  «protocol»
                │      └─ FoundationModelsFormatter   on-device LLM cleanup
                │             ▲ AppContext (frontmost bundle ID → tone)
                │
                └─> TextInjector    1. AX AXSelectedText
                                    2. pasteboard + synthetic ⌘V
```

Two seams are deliberate:

- **`TranscriptionEngine`** — swap in FluidAudio's Parakeet (Neural Engine,
  ~1.9% WER, fastest on Apple Silicon) or WhisperKit for wider multilingual
  coverage without touching the pipeline.
- **`TextFormatter`** — a cloud implementation (Claude) drops in here for
  Command Mode and a high-quality tier, off by default.

### Design notes

- **Pre-warming is the whole latency story.** `AVAudioEngine` is started at
  launch and the tap installed permanently; a dictation just opens a gate.
  Starting the engine on the keypress costs 150–300ms.
- **…but the microphone is released after 30s idle.** A permanently running
  engine keeps macOS's orange "mic in use" indicator lit, which makes a
  dictation app feel like it is always listening. `AudioCapture.suspend()`
  stops the engine while leaving the tap installed, so a burst of dictations
  all stay instant and only the first one after a pause pays the restart.
- **`AudioCapture` is `nonisolated`, deliberately.** The package sets
  `defaultIsolation(MainActor)`; without the opt-out the audio tap closure
  inherits MainActor, and Swift 6's executor assertion traps (SIGTRAP) when
  AVAudioEngine calls it on the real-time audio thread.
- **Streaming, not batching.** Audio goes to the analyzer while you hold, so
  key-up only finalizes the tail.
- **The HUD must never take key focus** — it's a `.nonactivatingPanel` with
  `canBecomeKey` forced false. Otherwise the target text field loses its cursor
  and injection lands nowhere.
- **Not sandboxed.** The sandbox denies both global event taps and the
  Accessibility APIs. This rules out the Mac App Store; Developer ID +
  notarization is the distribution path.

## Layout

```
Sources/Murmur/
  MurmurApp.swift            @main + AppDelegate (launch hook for pre-warming)
  Core/                      DictationController (state machine), AppContext
  Hotkey/HotkeyMonitor       CGEventTap modifier-hold detection
  Audio/AudioCapture         pre-warmed mic capture + format conversion
  Transcription/             protocol + AppleSpeechEngine
  Formatting/                protocol + FoundationModelsFormatter
  Injection/TextInjector     AX-then-paste strategy chain
  Permissions/               TCC state and prompts
  UI/                        menu bar, settings, floating HUD
Resources/                   Info.plist, entitlements
scripts/                     bundle.sh, make-cert.sh
```

## Commands

```bash
make build       # compile only
make run         # bundle, sign, launch
make release     # release build
make install     # copy to /Applications
make reset-tcc   # nuke permission grants if they get stuck
make clean
```

## Not built yet

- Command Mode (select text → "make this more formal")
- Personal dictionary learned from corrections
- Dictation history
- Parakeet / WhisperKit engines behind `TranscriptionEngine`
- VAD gating for silence trimming
- Launch at login
- App icon and branding
- Notarized distribution
