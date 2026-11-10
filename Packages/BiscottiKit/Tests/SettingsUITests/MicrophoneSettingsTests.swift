import Foundation
import Testing
@testable import SettingsUI

@Suite("Microphone settings")
struct MicrophoneSettingsTests {
    @Test("section caption points to macOS Sound settings")
    func inputCaption() {
        #expect(SettingsView.microphoneInputCaption.contains("System Settings"))
        #expect(SettingsView.soundSettingsURL != nil)
    }
}
