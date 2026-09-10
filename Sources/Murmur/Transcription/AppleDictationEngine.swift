import AVFoundation
import Foundation
import Speech

/// Apple's `DictationTranscriber` — the recogniser behind system Dictation.
///
/// The reason to choose it over `SpeechTranscriber` is spoken commands. It
/// resolves "new line", "period" and "comma" inside the recogniser, so
/// formatting is deterministic rather than something the cleanup model has to
/// infer from context (which it does about half the time).
///
/// The trade is that it is tuned for dictation rather than long-form prose.
final class AppleDictationEngine: TranscriptionEngine {
    let displayName = "Apple Dictation (on-device)"

    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<String, Never>?
    private var cachedFormat: AVAudioFormat?
    private let locale: Locale

    var biasStrings: [String] = []

    init(locale: Locale = .current) {
        self.locale = locale
    }

    var inputFormat: AVAudioFormat? {
        get async { cachedFormat }
    }

    func prepare() async throws {
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

    private func makeTranscriber() -> DictationTranscriber {
        // `punctuation` is the whole point of this engine: it turns spoken
        // "period", "comma" and "new line" into real characters at recognition
        // time. Emoji substitution is deliberately left off — dictating the
        // word "heart" should write the word.
        DictationTranscriber(
            locale: locale,
            contentHints: [],
            transcriptionOptions: [.punctuation],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }
}
