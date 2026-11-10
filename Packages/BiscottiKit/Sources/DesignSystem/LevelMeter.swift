import SwiftUI

/// Segmented horizontal audio level meter.
///
/// `fraction` is 0...1 across the meter's dB range (callers convert with
/// `AudioLevel.meterFraction`). Segments light sage for normal speech,
/// ochre near the top and red at clipping, so a glance shows both "is it
/// working" and "is it too hot".
public struct LevelMeter: View {
    private let fraction: Double
    private let segments: Int
    private let isActive: Bool

    /// - Parameters:
    ///   - fraction: Fill 0...1.
    ///   - segments: Number of segments (default 20).
    ///   - isActive: `false` dims the whole meter (e.g. no signal source).
    public init(fraction: Double, segments: Int = 20, isActive: Bool = true) {
        self.fraction = min(1, max(0, fraction))
        self.segments = max(1, segments)
        self.isActive = isActive
    }

    /// Fill boundaries for the colour bands, as fractions of the meter.
    static let warningStart = 0.75
    static let clipStart = 0.92

    /// Number of lit segments for `fraction`.
    static func litCount(fraction: Double, segments: Int) -> Int {
        Int((min(1, max(0, fraction)) * Double(segments)).rounded())
    }

    public var body: some View {
        let lit = Self.litCount(fraction: fraction, segments: segments)
        HStack(spacing: 2) {
            ForEach(0 ..< segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color(for: index, lit: lit))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 8)
        .opacity(isActive ? 1 : 0.4)
        .animation(.linear(duration: 0.12), value: lit)
        .accessibilityElement()
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }

    private func color(for index: Int, lit: Int) -> Color {
        guard index < lit, isActive else { return Tokens.neutralChip }
        let position = Double(index + 1) / Double(segments)
        if position > Self.clipStart { return .signalRed }
        if position > Self.warningStart { return .warningOchre }
        return .sage
    }
}

#Preview("Level meter") {
    VStack(spacing: 12) {
        LevelMeter(fraction: 0)
        LevelMeter(fraction: 0.45)
        LevelMeter(fraction: 0.85)
        LevelMeter(fraction: 1)
        LevelMeter(fraction: 0.6, isActive: false)
    }
    .padding()
    .frame(width: 240)
}
