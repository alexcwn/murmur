import AVFoundation
import Foundation
import Speech

/// Apple's on-device `SpeechAnalyzer` (macOS 26+), the same engine behind Notes
/// and Voice Memos. No model to vendor, no network in the transcription path.
final class AppleSpeechEngine: TranscriptionEngine {
    let displayName = "Apple Speech (on-device)"

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<String, Never>?
    private var cachedFormat: AVAudioFormat?
    private let locale: Locale

    /// Dictionary terms handed to the recogniser as context so it leans toward
    /// producing them. Deliberately capped by the caller — long context lists
    /// make these models drift and invent text on quiet audio.
    var biasStrings: [String] = []

    init(locale: Locale = .current) {
        self.locale = locale
    }

    var inputFormat: AVAudioFormat? {
        get async { cachedFormat }
    }

    func prepare() async throws {
        // First launch pays a one-time model download. Doing it here rather
        // than lazily is why the first dictation isn't several seconds slow.
        let probe = makeTranscriber()
        try await SpeechAssets.ensureInstalled(for: [probe], locale: locale)
        cachedFormat = await SpeechAssets.bestFormat(for: [probe])
    }

    func beginSession(onPartial: @escaping @Sendable (String) -> Void) async throws {
        await cancel()

        let transcriber = makeTranscriber()
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(
            bufferingPolicy: .bufferingNewest(512)
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.continuation = continuation

        if !biasStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings = [.general: biasStrings]
            try await analyzer.setContext(context)
        }

        try await analyzer.prepareToAnalyze(in: cachedFormat)
        try await analyzer.start(inputSequence: stream)

        // Volatile results arrive repeatedly and are superseded; finalized ones
        // are append-only. Track them separately so the HUD can show a live
        // transcript without the finalized text flickering.
        resultsTask = Task {
            var finalized = ""
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        finalized += text
                        onPartial(finalized)
                    } else {
                        onPartial(finalized + text)
                    }
                }
            } catch {
                // Stream errors surface through `finish()`; keep what we have.
            }
            return finalized
        }
    }

    func append(_ input: AnalyzerInput) async {
        continuation?.yield(input)
    }

    func finish() async throws -> String {
        guard let analyzer else { return "" }
        continuation?.finish()
        continuation = nil

        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = await resultsTask?.value ?? ""

        self.analyzer = nil
        self.transcriber = nil
        self.resultsTask = nil
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() async {
        continuation?.finish()
        continuation = nil
        resultsTask?.cancel()
        resultsTask = nil
        if let analyzer { await analyzer.cancelAndFinishNow() }
        analyzer = nil
        transcriber = nil
    }

    private func makeTranscriber() -> SpeechTranscriber {
        // `progressiveTranscription` streams volatile results as you speak,
        // which is what makes the HUD feel live.
        SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    }

}
