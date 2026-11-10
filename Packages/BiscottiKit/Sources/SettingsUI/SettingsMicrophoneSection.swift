import AppKit
import DesignSystem
import SwiftUI

// MARK: - Microphone section

extension SettingsView {
    /// Caption under the current input.
    static let microphoneInputCaption =
        "Biscotti records from your Mac's input. Change it in System Settings → Sound."

    /// Caption under the level test.
    static let microphoneTestCaption =
        "Speak normally: the bar should move well into the green. Levels here are before voice processing, so they can read lower than while recording."

    /// System Settings → Sound → Input.
    static let soundSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")

    var microphoneSection: some View {
        Section(Self.sectionTitles[1]) {
            VStack(alignment: .leading, spacing: Tokens.spacingXS) {
                HStack {
                    Text("Input")
                    Spacer()
                    Text(micSettings.currentInputText)
                        .foregroundStyle(Tokens.secondaryText)
                    if let url = Self.soundSettingsURL {
                        Button("Sound Settings\u{2026}") {
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                Text(Self.microphoneInputCaption)
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
}
