import Foundation
import Recording
import Testing
@testable import SettingsUI

@Suite("Microphone settings -- picker rows")
@MainActor
struct MicrophoneChoiceTests {
    private let builtIn = AudioInputDevice(uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone")
    private let usb = AudioInputDevice(uid: "AppleUSBAudioEngine:Shure:MV7", name: "Shure MV7")

    @Test("system default comes first and names the current default")
    func systemDefaultFirst() {
        let rows = MicrophoneSettingsViewModel.makeChoices(
            devices: [builtIn, usb], systemDefault: builtIn, saved: nil
        )
        let labels = rows.map(\.label)
        #expect(labels == ["System default (MacBook Pro Microphone)", "MacBook Pro Microphone", "Shure MV7"])
        #expect(rows[0].device == nil)
        #expect(rows[0].id == MicrophoneChoice.systemDefaultID)
    }

    @Test("system default without a device has a plain label")
    func noSystemDefault() {
        let rows = MicrophoneSettingsViewModel.makeChoices(devices: [], systemDefault: nil, saved: nil)
        let labels = rows.map(\.label)
        #expect(labels == ["System default"])
    }

    @Test("a saved device that is connected is not duplicated")
    func savedConnected() {
        let rows = MicrophoneSettingsViewModel.makeChoices(
            devices: [builtIn, usb], systemDefault: builtIn, saved: usb
        )
        #expect(rows.count == 3)
        let anyDisconnected = rows.contains { $0.isDisconnected }
        #expect(anyDisconnected == false)
    }

    @Test("a saved device that is disconnected stays visible and flagged")
    func savedDisconnected() {
        let rows = MicrophoneSettingsViewModel.makeChoices(
            devices: [builtIn], systemDefault: builtIn, saved: usb
        )
        #expect(rows.last?.label == "Shure MV7 (not connected)")
        #expect(rows.last?.isDisconnected == true)
        #expect(rows.last?.id == usb.uid)
    }
}

@Suite("Microphone settings -- store")
struct MicInputStoreTests {
    @Test("UserDefaults store round-trips the choice and clears it")
    func userDefaultsRoundTrip() throws {
        let suite = "MicInputStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsMicInputStore(defaults: defaults)
        let device = AudioInputDevice(uid: "AppleUSBAudioEngine:Shure:MV7", name: "Shure MV7")

        #expect(store.load() == nil)
        store.save(device)
        #expect(store.load() == device)
        store.save(nil)
        #expect(store.load() == nil)
    }
}
