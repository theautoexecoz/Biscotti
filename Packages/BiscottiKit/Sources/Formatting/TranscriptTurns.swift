import DataStore
import Foundation

/// Groups transcript segments into speaker turns for display and export.
///
/// Segment boundaries are transcription and diarization artifacts: a
/// speaker's single sentence is often split into several short segments.
/// Consecutive segments sharing the same non-nil `speakerID` collapse into
/// one turn, their text joined by a space. Segments with a nil `speakerID`
/// never collapse. Blank segments are dropped.
public enum TranscriptTurns {
    /// Returns one `SegmentData` per turn. Each turn keeps its first
    /// segment's `id`, speaker and `startTime` (so seeking jumps to the
    /// start of the turn) and its last segment's `endTime`.
    public static func merge(_ segments: [SegmentData]) -> [SegmentData] {
        var turns: [SegmentData] = []
        turns.reserveCapacity(segments.count)
        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let last = turns.last,
               let speakerID = segment.speakerID,
               speakerID == last.speakerID
            {
                turns[turns.count - 1] = SegmentData(
                    id: last.id,
                    speakerID: last.speakerID,
                    speakerLabel: last.speakerLabel,
                    startTime: last.startTime,
                    endTime: max(last.endTime, segment.endTime),
                    text: last.text + " " + text
                )
            } else {
                turns.append(SegmentData(
                    id: segment.id,
                    speakerID: segment.speakerID,
                    speakerLabel: segment.speakerLabel,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    text: text
                ))
            }
        }
        return turns
    }
}
