import AVFoundation
import Foundation
import Observation
import OSLog

/// Owns the push-to-talk pipeline and the state machine every view reads.
///
///     key down ──> capture ──> stream to engine ──> (key up) ──> finalize
///                                                        ──> clean up
///                                                        ──> apply dictionary
///                                                        ──> insert + record
@Observable
final class DictationController {
    enum State: Equatable {
        case starting
        case idle
        case listening
        case thinking
        case needsPermissions
        case failed(String)

        var symbolName: String {
            switch self {
            case .starting: "circle.dotted"
            case .idle: "mic"
            case .listening: "mic.fill"
            case .thinking: "ellipsis.circle"
            case .needsPermissions: "exclamationmark.triangle"
            case .failed: "xmark.octagon"
            }
        }

        var label: String {
            switch self {
            case .starting: "Warming up…"
            case .idle: "Ready"
            case .listening: "Listening"
            case .thinking: "Transcribing"
            case .needsPermissions: "Permissions needed"
            case .failed(let message): message
            }
        }
    }

    /// How the current capture was started. Determines where the text goes.
    enum CaptureMode {
        /// Hotkey held while another app was focused — text is injected there.
        case hotkey
        /// Started from the window's transport. Murmur itself is frontmost, so
        /// there is nothing sensible to inject into; the text is kept instead.
        case manual
    }

    private(set) var state: State = .starting
    private(set) var liveTranscript = ""
    private(set) var captureMode: CaptureMode = .hotkey
    /// 0…1, driven by the audio tap. Read by the VU meter.
    private(set) var inputLevel: Float = 0
    private(set) var captureStarted: Date?
    /// Nil when the cleanup pass is working; otherwise why it is not.
    private(set) var cleanupUnavailable: String?

    var rawMode: Bool {
        get { settings.values.rawMode }
        set { settings.values.rawMode = newValue }
    }

    var hotkey: Hotkey {
        get { settings.values.hotkey }
        set { settings.values.hotkey = newValue; monitor.hotkey = newValue }
    }

    let permissions = PermissionsManager()
    let history: HistoryStore
    let dictionaryStore: DictionaryStore
    let settings: SettingsStore

    private let log = Logger(subsystem: "com.alexchoo.murmur", category: "pipeline")
    private let monitor = HotkeyMonitor()
    private let audio = AudioCapture()
    private let injector = TextInjector()
    private let hud = HUDController()
    private var engine: any TranscriptionEngine
    private var formatter: any TextFormatter = FoundationModelsFormatter()

    private var targetContext = AppContext.unknown
    private var sessionTask: Task<Void, Never>?
    private var idleSuspendTask: Task<Void, Never>?

    init(
        history: HistoryStore = HistoryStore(),
        dictionaryStore: DictionaryStore = DictionaryStore(),
        settings: SettingsStore = SettingsStore()
    ) {
        self.history = history
        self.dictionaryStore = dictionaryStore
        self.settings = settings
        self.engine = AppleSpeechEngine(locale: settings.locale)

        monitor.hotkey = settings.values.hotkey
        monitor.onPress = { [weak self] in self?.beginDictation(mode: .hotkey) }
        monitor.onRelease = { [weak self] in self?.endDictation() }
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        await permissions.refresh()
        EntryValidator.warmUp()

        guard permissions.allGranted else {
            state = .needsPermissions
            return
        }

        do {
            refreshBias()
            try await engine.prepare()
            try audio.prewarm()
            await formatter.prepare()
            cleanupUnavailable = formatter.unavailableReason
        } catch {
            log.error("bootstrap failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
            return
        }

        guard monitor.start() else {
            state = .needsPermissions
            return
        }
        state = .idle
        scheduleIdleSuspend()
    }

    func shutdown() {
        idleSuspendTask?.cancel()
        monitor.stop()
        audio.teardown()
    }

    /// Pushes the current dictionary at the recogniser. Cheap, so it runs on
    /// every capture rather than trying to track dictionary edits.
    private func refreshBias() {
        engine.biasStrings = CorrectionEngine.biasStrings(from: dictionaryStore.dictionary)
    }

    // MARK: - Capture

    /// Transport button in the main window.
    func toggleManualCapture() {
        switch state {
        case .idle: beginDictation(mode: .manual)
        case .listening: endDictation()
        default: break
        }
    }

    private func beginDictation(mode: CaptureMode) {
        guard state == .idle else { return }

        idleSuspendTask?.cancel()
        idleSuspendTask = nil
        captureMode = mode
        targetContext = mode == .hotkey ? AppContext.frontmost() : .unknown
        liveTranscript = ""
        captureStarted = .now
        state = .listening
        refreshBias()

        audio.level.setSink { [weak self] value in
            Task { @MainActor in self?.inputLevel = value }
        }

        // The floating HUD is for dictating into another app; in manual mode the
        // window is already showing everything it would.
        if mode == .hotkey { hud.show(state: .listening, transcript: "") }

        sessionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try self.audio.beginCapture(format: await self.engine.inputFormat)
                try await self.engine.beginSession { [weak self] partial in
                    Task { @MainActor in self?.updateLiveTranscript(partial) }
                }
                for await input in stream {
                    await self.engine.append(input)
                }
            } catch {
                self.log.error("capture failed: \(error.localizedDescription)")
                await self.fail(error)
            }
        }
    }

    private func endDictation() {
        guard state == .listening else { return }
        let mode = captureMode
        let started = captureStarted ?? .now
        state = .thinking
        if mode == .hotkey { hud.show(state: .thinking, transcript: liveTranscript) }
        audio.endCapture()
        audio.level.setSink(nil)
        inputLevel = 0

        Task { [weak self] in
            guard let self else { return }
            await self.sessionTask?.value

            do {
                let raw = try await self.engine.finish()
                guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.finishIdle()
                    return
                }

                let cleaned = self.rawMode
                    ? raw
                    : await self.formatter.format(raw, context: self.targetContext)

                // The dictionary runs last, after the cleanup model, so nothing
                // downstream can undo it. This is the guaranteed path.
                let corrected = self.dictionaryStore.engine.apply(to: cleaned)

                if mode == .hotkey {
                    self.injector.inject(corrected.text, into: self.targetContext)
                }

                self.history.add(Transcription(
                    raw: raw,
                    text: corrected.text,
                    appName: mode == .hotkey ? self.targetContext.appName : nil,
                    duration: Date().timeIntervalSince(started),
                    corrections: corrected.applied,
                    wasInjected: mode == .hotkey
                ))
                self.finishIdle()
            } catch {
                self.log.error("finalize failed: \(error.localizedDescription)")
                await self.fail(error)
            }
        }
    }

    private func updateLiveTranscript(_ partial: String) {
        liveTranscript = partial
        if captureMode == .hotkey { hud.show(state: .listening, transcript: partial) }
    }

    private func finishIdle() {
        state = .idle
        liveTranscript = ""
        captureStarted = nil
        hud.hide()
        scheduleIdleSuspend()
    }

    /// Releases the microphone once you've stopped dictating for a while, so the
    /// system "mic in use" indicator isn't lit while the app merely sits open.
    private func scheduleIdleSuspend() {
        idleSuspendTask?.cancel()
        let timeout = settings.values.idleTimeoutSeconds
        idleSuspendTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self, self.state == .idle else { return }
            self.audio.suspend()
        }
    }

    private func fail(_ error: any Error) async {
        await engine.cancel()
        audio.endCapture()
        audio.level.setSink(nil)
        inputLevel = 0
        hud.hide()
        state = .failed(error.localizedDescription)

        try? await Task.sleep(for: .seconds(3))
        if case .failed = state { state = .idle }
    }
}
