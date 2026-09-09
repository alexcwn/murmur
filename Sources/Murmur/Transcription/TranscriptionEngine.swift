import AVFoundation
import Speech

/// The seam that lets us swap Apple's SpeechAnalyzer for Parakeet (FluidAudio)
/// or WhisperKit without touching the pipeline.
///
/// Everything is streaming: buffers go in while the key is held, and `finish()`
/// only has to finalize the tail. Batching the whole utterance on key-up would
/// add the full transcription time to the user's perceived latency.
protocol TranscriptionEngine: AnyObject {
    var displayName: String { get }

    /// Audio format the engine wants. `nil` means "whatever the mic gives you".
    var inputFormat: AVAudioFormat? { get async }

    /// Words the engine should lean toward producing. Engines that cannot bias
    /// may ignore this; the correction pass is the guaranteed path either way.
    var biasStrings: [String] { get set }

    /// Download models, warm caches. Called once at launch, never on a keypress.
    func prepare() async throws

    func beginSession(onPartial: @escaping @Sendable (String) -> Void) async throws
    func append(_ input: AnalyzerInput) async
    func finish() async throws -> String
    func cancel() async
}
