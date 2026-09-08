import AVFoundation
import Foundation
import Observation
import OSLog

/// Owns the push-to-talk pipeline and the state machine every other component reads.
///
///     Fn down ──> capture ──> stream to engine ──> (Fn up) ──> finalize
///                                                      ──> format ──> inject
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

    private(set) var state: State = .starting
    private(set) var liveTranscript = ""
    private(set) var lastInsertion = ""

    var hotkey: Hotkey {
        didSet { monitor.hotkey = hotkey }
    }

    /// Skip the LLM cleanup pass and inject the raw transcript. Useful when
    /// dictating code or identifiers, where "cleanup" is mostly damage.
    var rawMode = false

    let permissions = PermissionsManager()

    private let log = Logger(subsystem: "com.alexchoo.murmur", category: "pipeline")
    private let monitor = HotkeyMonitor()
    private let audio = AudioCapture()
    private let injector = TextInjector()
    private let hud = HUDController()
    private var engine: any TranscriptionEngine = AppleSpeechEngine()
    private var formatter: any TextFormatter = FoundationModelsFormatter()

    /// The app the user was focused on when they pressed the key. Captured on
    /// key-down because our own HUD must never become frontmost, but a Space
    /// switch mid-dictation would otherwise send text to the wrong window.
    private var targetContext = AppContext.unknown
    private var sessionTask: Task<Void, Never>?

    /// How long the microphone stays warm after a dictation. Long enough that a
    /// burst of dictations all feel instant, short enough that the orange
    /// "mic in use" indicator isn't lit while you're not using the app.
    private static let idleTimeout: Duration = .seconds(30)
    private var idleSuspendTask: Task<Void, Never>?

    init(hotkey: Hotkey = .fn) {
        self.hotkey = hotkey
        monitor.hotkey = hotkey
        monitor.onPress = { [weak self] in self?.beginDictation() }
        monitor.onRelease = { [weak self] in self?.endDictation() }
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        await permissions.refresh()
        guard permissions.allGranted else {
            state = .needsPermissions
            return
        }

        do {
            // Pre-warming matters more than anything else for perceived latency.
            // The speech model download and the audio device negotiation both
            // cost hundreds of milliseconds; neither should land on a keypress.
            try await engine.prepare()
            try audio.prewarm()
            await formatter.prepare()
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

    // MARK: - Push to talk

    private func beginDictation() {
        guard state == .idle else { return }

        idleSuspendTask?.cancel()
        idleSuspendTask = nil
        targetContext = AppContext.frontmost()
        liveTranscript = ""
        state = .listening
        hud.show(state: .listening, transcript: "")

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
        state = .thinking
        hud.show(state: .thinking, transcript: liveTranscript)
        audio.endCapture()

        Task { [weak self] in
            guard let self else { return }
            // Let the capture loop drain into the engine before finalizing.
            await self.sessionTask?.value

            do {
                let raw = try await self.engine.finish()
                guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.finishIdle()
                    return
                }

                let text = self.rawMode
                    ? raw
                    : await self.formatter.format(raw, context: self.targetContext)

                self.injector.inject(text, into: self.targetContext)
                self.lastInsertion = text
                self.finishIdle()
            } catch {
                self.log.error("finalize failed: \(error.localizedDescription)")
                await self.fail(error)
            }
        }
    }

    private func updateLiveTranscript(_ partial: String) {
        liveTranscript = partial
        hud.show(state: .listening, transcript: partial)
    }

    private func finishIdle() {
        state = .idle
        liveTranscript = ""
        hud.hide()
        scheduleIdleSuspend()
    }

    /// Releases the microphone once you've stopped dictating for a while.
    /// `beginCapture` transparently restarts the engine on the next keypress.
    private func scheduleIdleSuspend() {
        idleSuspendTask?.cancel()
        idleSuspendTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTimeout)
            guard !Task.isCancelled, let self, self.state == .idle else { return }
            self.audio.suspend()
        }
    }

    private func fail(_ error: any Error) async {
        await engine.cancel()
        audio.endCapture()
        hud.hide()
        state = .failed(error.localizedDescription)

        // Don't strand the app in a failed state — a transient device glitch
        // shouldn't require a relaunch.
        try? await Task.sleep(for: .seconds(3))
        if case .failed = state { state = .idle }
    }
}
