import DataStore
import Foundation
import Testing
@testable import Intelligence

@Suite("SilenceHallucination")
struct SilenceHallucinationTests {
    private func segments(_ texts: [String]) -> [SegmentData] {
        texts.enumerated().map { index, text in
            SegmentData(
                id: UUID(), speakerID: 0, speakerLabel: "Speaker 1",
                startTime: Double(index), endTime: Double(index) + 1, text: text
            )
        }
    }

    @Test("a lone Thank you is a silence hallucination")
    func loneThankYou() {
        #expect(SilenceHallucination.isOnlyHallucination(segments(["Thank you."])))
    }

    @Test("bracketed markers and repeats count")
    func markers() {
        #expect(SilenceHallucination.isOnlyHallucination(segments(["[BLANK_AUDIO]", " Thank you! ", "(music)"])))
    }

    @Test("any real speech means it is not a hallucination")
    func realSpeech() {
        #expect(!SilenceHallucination.isOnlyHallucination(segments(["Thank you.", "Let's get started"])))
        #expect(!SilenceHallucination.isOnlyHallucination(segments(["Hello"])))
    }

    @Test("no segments is not classified here (handled as empty)")
    func noSegments() {
        #expect(!SilenceHallucination.isOnlyHallucination([]))
        #expect(!SilenceHallucination.isOnlyHallucination(segments(["  "])))
    }

    @Test("normalise strips punctuation and case")
    func normalise() {
        #expect(SilenceHallucination.normalise("  Thank-you!! ") == "thank you")
    }
}
