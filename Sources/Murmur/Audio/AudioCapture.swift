import AVFoundation
import Speech

/// Microphone capture that stays warm between dictations.
///
/// The engine is started once at launch and the input tap is installed
/// permanently; a capture "session" just flips a gate and hands out a fresh
/// stream. Starting `AVAudioEngine` on the keypress instead costs 150–300ms of
/// device negotiation, which is most of the latency budget for the whole app.
///
/// `nonisolated` is load-bearing. The package sets `defaultIsolation(MainActor)`,
/// which would otherwise make the tap closure below MainActor-isolated. Swift 6
/// then emits an executor assertion inside it, and since AVAudioEngine invokes
/// the tap on a real-time audio thread, that assertion fails and traps
/// (`dispatch_assert_queue` → SIGTRAP) the moment the first buffer arrives.
/// Everything here is thread-safe on its own terms: `Gate` holds the lock, and
/// the engine is only touched from the main thread via `DictationController`.
nonisolated final class AudioCapture {
    /// Shared with the real-time audio thread, so it carries its own lock.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: AsyncStream<AnalyzerInput>.Continuation?
        private var converter: AVAudioConverter?
        private var targetFormat: AVAudioFormat?

        func open(
            continuation: AsyncStream<AnalyzerInput>.Continuation,
            converter: AVAudioConverter?,
            targetFormat: AVAudioFormat?
        ) {
            lock.lock()
            defer { lock.unlock() }
            self.continuation = continuation
            self.converter = converter
            self.targetFormat = targetFormat
        }

        func close() {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            self.converter = nil
            self.targetFormat = nil
            lock.unlock()
            continuation?.finish()
        }

        /// Called on the audio thread. Must not allocate unboundedly or block.
        func submit(_ buffer: AVAudioPCMBuffer) {
            lock.lock()
            let continuation = self.continuation
            let converter = self.converter
            let targetFormat = self.targetFormat
            lock.unlock()

            guard let continuation else { return }
            let outgoing: AVAudioPCMBuffer
            if let converter, let targetFormat {
                guard let converted = Gate.convert(buffer, using: converter, to: targetFormat) else { return }
                outgoing = converted
            } else {
                guard let copy = Gate.copy(buffer) else { return }
                outgoing = copy
            }
            continuation.yield(AnalyzerInput(buffer: outgoing))
        }

        private static func convert(
            _ buffer: AVAudioPCMBuffer,
            using converter: AVAudioConverter,
            to format: AVAudioFormat
        ) -> AVAudioPCMBuffer? {
            let ratio = format.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

            // AVAudioConverter's block is typed @Sendable but is invoked
            // synchronously on this thread before `convert` returns. A reference
            // box carries the "already supplied" flag without tripping the
            // concurrent-capture diagnostic, and lets us pass the caller's
            // buffer through despite AVAudioPCMBuffer not being Sendable.
            final class Feed: @unchecked Sendable {
                let buffer: AVAudioPCMBuffer
                var consumed = false
                init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
            }
            let feed = Feed(buffer)
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if feed.consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                feed.consumed = true
                status.pointee = .haveData
                return feed.buffer
            }
            guard error == nil, output.frameLength > 0 else { return nil }
            return output
        }

        /// The tap's buffer is reused by CoreAudio, so anything we hand across a
        /// thread boundary has to be our own copy.
        private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
            guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
                  let source = buffer.floatChannelData,
                  let destination = copy.floatChannelData
            else { return nil }
            copy.frameLength = buffer.frameLength
            let frames = Int(buffer.frameLength)
            for channel in 0..<Int(buffer.format.channelCount) {
                destination[channel].update(from: source[channel], count: frames)
            }
            return copy
        }
    }

    private let engine = AVAudioEngine()
    private let gate = Gate()
    private var isTapInstalled = false
    private var isRunning = false

    /// True while the engine holds the microphone — which is exactly when macOS
    /// shows the orange "mic in use" indicator.
    var isMicrophoneLive: Bool { isRunning }

    /// Installs the tap and starts the engine. The tap survives suspend/resume,
    /// so this is only the first-run cost.
    func prewarm() throws {
        try installTapIfNeeded()
        try startEngine()
    }

    private func installTapIfNeeded() throws {
        guard !isTapInstalled else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw CaptureError.noInputDevice
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [gate] buffer, _ in
            gate.submit(buffer)
        }
        isTapInstalled = true
    }

    private func startEngine() throws {
        guard !isRunning else { return }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    /// Releases the microphone while keeping the tap installed, so the orange
    /// indicator clears when you aren't dictating. Restarting afterwards costs
    /// 150–300ms, which is why we only do this after an idle period rather than
    /// after every utterance.
    func suspend() {
        guard isRunning else { return }
        engine.stop()
        isRunning = false
    }

    /// Opens the gate and returns the buffers for one dictation.
    func beginCapture(format targetFormat: AVAudioFormat?) throws -> AsyncStream<AnalyzerInput> {
        try prewarm()

        let sourceFormat = engine.inputNode.outputFormat(forBus: 0)
        var converter: AVAudioConverter?
        if let targetFormat, targetFormat != sourceFormat {
            converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
            guard converter != nil else { throw CaptureError.unsupportedFormat }
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(
            bufferingPolicy: .bufferingNewest(512)
        )
        gate.open(
            continuation: continuation,
            converter: converter,
            targetFormat: converter == nil ? nil : targetFormat
        )
        return stream
    }

    func endCapture() {
        gate.close()
    }

    func teardown() {
        gate.close()
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        if isRunning {
            engine.stop()
            isRunning = false
        }
    }

    enum CaptureError: LocalizedError {
        case noInputDevice
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .noInputDevice: "No microphone is available."
            case .unsupportedFormat: "This microphone's format can't be converted for transcription."
            }
        }
    }
}
