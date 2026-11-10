import DesignSystem
import SwiftUI

// MARK: - Microphone section

extension SettingsView {
    /// Caption under the input picker.
    static let microphoneChoiceCaption =
        "While recording, Biscotti makes this your Mac's input (so your meeting app uses it too) and switches back when you stop. Changes apply from the next recording."

    /// Caption under the level test.
    static let microphoneTestCaption =
        "Speak normally: the bar should move well into the green. Levels here are before voice processing, so they can read lower than while recording."

    var microphoneSection: some View {
        Section(Self.sectionTitles[1]) {
            VStack(alignment: .leading, spacing: Tokens.spacingXS) {
                Picker("Input device", selection: microphoneSelectionBinding) {
                    ForEach(micSettings.choices) { choice in
                        Text(choice.label).tag(choice.id)
                    }
                }
                Text(Self.microphoneChoiceCaption)
                    .font(Tokens.metadataFont)
                    .foregroundStyle(Tokens.secondaryText)
            }

            VStack(alignment: .leading, spacing: Tokens.spacingSM) {
                HStack(spacing: Tokens.spacingSM) {
                    Text("Test level")
                    LevelMeter(fraction: micSettings.testFraction, isActive: micSettings.isTesting)
                        .frame(maxWidth: 220)
                    Spacer(minLength: 0)
                    Button(micSettings.isTesting ? "Stop" : "Test") {
                        if micSettings.isTesting {
                            micSettings.stopTest()
                        } else {
                            micSettings.refresh()
                            micSettings.startTest()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!micSettings.canTest && !micSettings.isTesting)
                }
                if let error = micSettings.testError {
                    Text(error)
                        .font(Tokens.metadataFont)
                        .foregroundStyle(Color.signalRedText)
                } else if let reason = micSettings.testUnavailableReason {
                    Text(reason)
                        .font(Tokens.metadataFont)
                        .foregroundStyle(Tokens.secondaryText)
                } else {
                    Text(Self.microphoneTestCaption)
                        .font(Tokens.metadataFont)
                        .foregroundStyle(Tokens.secondaryText)
                }
            }
        }
        .onAppear { micSettings.refresh() }
        .onDisappear { micSettings.stopTest() }
    }

    private var microphoneSelectionBinding: Binding<String> {
        Binding(
            get: { micSettings.selectedID },
            set: { micSettings.select(id: $0) }
        )
    }
}
