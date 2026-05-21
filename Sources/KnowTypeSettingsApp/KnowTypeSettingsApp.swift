import KnowTypeSettingsUI
import SwiftUI

@main
struct KnowTypeSettingsApp: App {
    var body: some Scene {
        WindowGroup(SettingsLocalization.string("settings.window.title")) {
            KnowTypeSettingsRootView()
                .frame(minWidth: 840, minHeight: 560)
        }
    }
}
