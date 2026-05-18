import KnowTypeSettingsUI
import SwiftUI

@main
struct KnowTypeSettingsApp: App {
    var body: some Scene {
        WindowGroup("KnowType Settings") {
            KnowTypeSettingsRootView()
                .frame(minWidth: 840, minHeight: 560)
        }
    }
}
