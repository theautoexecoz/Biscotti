import DataStore
import Foundation

/// Detects transcripts made only of phrases speech-to-text models commonly
/// invent from silence or noise (e.g. a lone "Thank you.").
///
/// Auto-enhancement treats such a transcript as empty, so a silent recording
/// gets the canned empty result instead of an AI summary of nothing. Narrow
/// on purpose: any segment outside the list means real speech.
enum SilenceHallucination {
    /// Normalised phrases (lowercase, letters and spaces only).
    static let phrases: Set<String> = [
        "thank you", "thanks", "thank you very much",
        "thank you for watching", "thanks for watching",
        "you", "bye", "bye bye",
        "music", "blank audio", "silence"
    ]

    /// `true` when there is at least one segment and every non-blank
    /// segment is a known silence phrase.
    static func isOnlyHallucination(_ segments: [SegmentData]) -> Bool {
        let texts = segments.map { normalise($0.text) }.filter { !$0.isEmpty }
        guard !texts.isEmpty else { return false }
        return texts.allSatisfy { phrases.contains($0) }
    }

    static func normalise(_ text: String) -> String {
        let letters = text.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.letters.contains(scalar) ? Character(scalar) : " "
        }
        return String(letters)
            .split(separator: " ")
            .joined(separator: " ")
    }
}
