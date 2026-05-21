import KnowTypeSettingsUI
import SwiftUI

@main
struct KnowTypeSettingsApp: App {
    var body: some Scene {
        WindowGroup("KnowType 设置") {
            KnowTypeSettingsRootView()
                .frame(minWidth: 840, minHeight: 560)
        }
    }
}
