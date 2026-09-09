import XCTest
@testable import Murmur

final class CorrectionEngineTests: XCTestCase {

    private func engine(
        corrections: [(String, String)] = [],
        terms: [String] = []
    ) -> CorrectionEngine {
        CorrectionEngine(dictionary: MurmurDictionary(
            terms: terms.map { DictionaryTerm(text: $0) },
            corrections: corrections.map { DictionaryCorrection(heard: $0.0, write: $0.1) }
        ))
    }

    // MARK: - The glued-word requirement

    func testCatchesSpacedHyphenatedAndGluedForms() {
        let e = engine(corrections: [("cloud code", "Claude Code")])
        for input in ["cloud code", "CloudCode", "Cloud-Code", "cloud  code", "Cloud Code", "cloud_code"] {
            XCTAssertEqual(e.apply(to: input).text, "Claude Code", "failed on: \(input)")
        }
    }

    func testCorrectsInsideASentence() {
        let e = engine(corrections: [("cloud code", "Claude Code")])
        XCTAssertEqual(
            e.apply(to: "I opened cloud code and shipped it.").text,
            "I opened Claude Code and shipped it."
        )
    }

    // MARK: - Must not corrupt real words

    func testLeavesCloudflareAlone() {
        let e = engine(corrections: [("cloud code", "Claude Code")])
        XCTAssertEqual(e.apply(to: "We host it on Cloudflare.").text, "We host it on Cloudflare.")
    }

    func testLeavesBareCloudAlone() {
        let e = engine(corrections: [("cloud code", "Claude Code")])
        XCTAssertEqual(e.apply(to: "Move it to the cloud today.").text, "Move it to the cloud today.")
    }

    func testDoesNotMatchAcrossAWordBoundaryOnTheRight() {
        let e = engine(corrections: [("cloud code", "Claude Code")])
        XCTAssertEqual(e.apply(to: "the cloud codes are wrong").text, "the cloud codes are wrong")
    }

    func testDoesNotMatchWhenGluedIntoALongerWord() {
        let e = engine(corrections: [("cloud code", "Claude Code")])
        XCTAssertEqual(e.apply(to: "MyCloudCodebase").text, "MyCloudCodebase")
    }

    // MARK: - Ordering

    func testLongestMatchWins() {
        let e = engine(corrections: [
            ("cloud", "Cloud"),
            ("cloud code", "Claude Code"),
        ])
        XCTAssertEqual(e.apply(to: "cloud code").text, "Claude Code")
    }

    func testShorterRuleStillFiresElsewhere() {
        let e = engine(corrections: [
            ("cloud", "Cloud"),
            ("cloud code", "Claude Code"),
        ])
        XCTAssertEqual(e.apply(to: "cloud code and cloud").text, "Claude Code and Cloud")
    }

    // MARK: - Terms normalise casing

    func testTermFixesCasing() {
        let e = engine(terms: ["Supabase"])
        XCTAssertEqual(e.apply(to: "we use supabase for auth").text, "we use Supabase for auth")
    }

    func testTermAlreadyCorrectReportsNothing() {
        let e = engine(terms: ["Supabase"])
        let r = e.apply(to: "we use Supabase")
        XCTAssertEqual(r.text, "we use Supabase")
        XCTAssertTrue(r.applied.isEmpty)
    }

    func testTermDoesNotFireInsideALongerWord() {
        let e = engine(terms: ["Vercel"])
        XCTAssertEqual(e.apply(to: "vercelian nonsense").text, "vercelian nonsense")
    }

    // MARK: - Reporting

    func testReportsWhatChanged() {
        let e = engine(corrections: [("cloud code", "Claude Code")], terms: ["Supabase"])
        let r = e.apply(to: "cloud code with supabase")
        XCTAssertEqual(r.text, "Claude Code with Supabase")
        XCTAssertEqual(r.applied.count, 2)
        XCTAssertEqual(r.applied.first?.matched, "cloud code")
        XCTAssertEqual(r.applied.first?.replacement, "Claude Code")
        XCTAssertEqual(r.applied.first?.source, .correction)
        XCTAssertEqual(r.applied.last?.source, .term)
    }

    func testEmptyDictionaryIsANoOp() {
        let r = engine().apply(to: "nothing to do here")
        XCTAssertEqual(r.text, "nothing to do here")
        XCTAssertTrue(r.applied.isEmpty)
    }

    // MARK: - Bias list

    func testBiasListPrefersCorrectionsAndDeduplicates() {
        let d = MurmurDictionary(
            terms: [DictionaryTerm(text: "Supabase"), DictionaryTerm(text: "Claude Code")],
            corrections: [DictionaryCorrection(heard: "cloud code", write: "Claude Code")]
        )
        let bias = CorrectionEngine.biasStrings(from: d)
        XCTAssertEqual(bias.first, "Claude Code")
        XCTAssertEqual(bias.filter { $0 == "Claude Code" }.count, 1)
    }

    func testBiasListIsCapped() {
        let d = MurmurDictionary(terms: (0..<400).map { DictionaryTerm(text: "term\($0)") })
        XCTAssertEqual(CorrectionEngine.biasStrings(from: d, limit: 100).count, 100)
    }
}
