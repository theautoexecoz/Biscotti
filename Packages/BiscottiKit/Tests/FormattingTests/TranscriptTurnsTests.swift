import DataStore
import Foundation
import Testing
import Formatting

@Suite("TranscriptTurns")
struct TranscriptTurnsTests {
    private func segment(
        _ text: String, speaker: Int?, start: TimeInterval, end: TimeInterval, label: String = "Speaker"
    ) -> SegmentData {
        SegmentData(id: UUID(), speakerID: speaker, speakerLabel: label, startTime: start, endTime: end, text: text)
    }

    @Test("consecutive segments from one speaker become one turn")
    func mergesSameSpeaker() {
        let first = segment("Look,", speaker: 1, start: 553, end: 554)
        let segments = [
            first,
            segment("we're in a position right now", speaker: 1, start: 554, end: 556),
            segment("we can do whatever we want.", speaker: 1, start: 556, end: 558)
        ]
        let turns = TranscriptTurns.merge(segments)
        #expect(turns.count == 1)
        #expect(turns[0].text == "Look, we're in a position right now we can do whatever we want.")
        #expect(turns[0].id == first.id)
        #expect(turns[0].startTime == 553)
        #expect(turns[0].endTime == 558)
    }

    @Test("a speaker change starts a new turn")
    func splitsOnSpeakerChange() {
        let segments = [
            segment("Yeah.", speaker: 1, start: 0, end: 1),
            segment("Because in reality,", speaker: 2, start: 1, end: 2),
            segment("no one's coming to us.", speaker: 2, start: 2, end: 3),
            segment("No, exactly.", speaker: 1, start: 3, end: 4)
        ]
        let texts = TranscriptTurns.merge(segments).map(\.text)
        #expect(texts == ["Yeah.", "Because in reality, no one's coming to us.", "No, exactly."])
    }

    @Test("segments without a speaker never merge, and blanks are dropped")
    func nilSpeakerAndBlanks() {
        let segments = [
            segment("One.", speaker: nil, start: 0, end: 1),
            segment("   ", speaker: nil, start: 1, end: 2),
            segment("Two.", speaker: nil, start: 2, end: 3)
        ]
        let texts = TranscriptTurns.merge(segments).map(\.text)
        #expect(texts == ["One.", "Two."])
    }

    @Test("empty input gives no turns")
    func empty() {
        #expect(TranscriptTurns.merge([]).isEmpty)
    }
}
