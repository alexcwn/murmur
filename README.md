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

Murmur is a normal Mac app: Dock icon, app menu, resizable window, Settings on
⌘,. The menu bar item is secondary — status and a recording toggle for when
you're working in another app.

Grant three permissions on first run (Settings → Permissions):

| Permission | Why |
|---|---|
| Microphone | Hear you while the key is held |
| Accessibility | Insert text at your cursor in other apps |
| Input Monitoring | Detect the push-to-talk key globally |

If you use the default **Fn** hotkey, also set System Settings → Keyboard →
"Press 🌐 key to" → **Do Nothing**, or the globe key opens the emoji picker at
the same time.

## The window

- **Transport deck** — VU meter with real ballistics, counter, record lamp,
  Record/Stop, raw-mode switch.
- **Transcriptions** — searchable history with copy on each entry, and an
  inline record of which dictionary corrections fired.
- **Dictionary** — words to teach it, and "when you hear X, write Y" pairs.

Two capture routes, deliberately different:

- **Hold the hotkey** in another app → text is inserted at your cursor.
- **Press Record** in the window → Murmur is frontmost, so there is nothing
  sensible to inject into; the transcription is kept in history instead.

## The dictionary

Lives at `~/Library/Application Support/Murmur/dictionary.json` and is meant to
be edited by hand as well as in the UI — external edits are picked up live.

It works two ways, because neither is sufficient alone:

1. **Bias before transcription.** Terms are passed to the recogniser as
   contextual strings so it leans toward producing them. Capped at 100 entries:
   long context lists make these models drift and invent text on quiet audio.
2. **Correct after transcription.** Runs last, after the cleanup model, so
   nothing downstream can undo it. Whole-word, case-insensitive, longest match
   first.

The correction pass tolerates the ways models glue words together — one rule for
`cloud code` also catches `CloudCode` and `Cloud-Code` — while anchoring on
alphanumeric boundaries so it can never fire inside `Cloudflare`, and never on
the ordinary word `cloud` alone. Adding a single common English word as a match
target raises a warning in the UI.

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

- **`TranscriptionEngine`** — two Apple engines ship today, selectable in
  Settings → Model and swapped live without a relaunch:
  - **Prose** (`SpeechTranscriber`) — tuned for continuous speech, 30 locales.
  - **Dictation** (`DictationTranscriber`) — what system Dictation uses. Resolves
    spoken commands (“new line”, “period”, “comma”) inside the recogniser rather
    than leaving them to the cleanup model, and covers 54 locales.

  FluidAudio's Parakeet or WhisperKit drop in behind the same protocol.
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
- **The design system is `Sources/Murmur/Design/Tokens.swift`**, mirroring
  `docs/tokens.html`. Every view reads from it; no component declares a literal
  color, size, radius or duration. 1980s field recorder — two decks rather than
  one theme inverted, radii capped at 5pt, and a VU needle on the real 300ms
  ballistic rather than a bar graph.

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

- App icon (the Dock shows the generic placeholder)
- Command Mode (select text → "make this more formal")
- Learning corrections automatically from edits
- Parakeet / WhisperKit engines behind `TranscriptionEngine`
- VAD gating for silence trimming
- Launch at login
- Notarized distribution

`Tests/MurmurTests` covers the correction engine. `swift test` needs XCTest,
which ships with Xcode rather than Command Line Tools, so it does not run on a
CLT-only machine — CI runs it on every push instead (`macos-26` runners have
Xcode preinstalled). Plain `swift build` is unaffected either way.
