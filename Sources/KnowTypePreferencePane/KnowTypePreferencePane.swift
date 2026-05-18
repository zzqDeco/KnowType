import Foundation

#if canImport(PreferencePanes)
@preconcurrency import AppKit
import KnowTypeSettingsUI
import PreferencePanes
@preconcurrency import SwiftUI

@objc(KnowTypePreferencePane)
public final class KnowTypePreferencePane: NSPreferencePane {
    private var hostingView: NSView?

    public override func mainViewDidLoad() {
        super.mainViewDidLoad()
        installSettingsView()
    }

    private func installSettingsView() {
        let view = NSHostingView(
            rootView: KnowTypeSettingsRootView()
                .frame(minWidth: 840, minHeight: 560)
        )
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 620)
        view.autoresizingMask = [.width, .height]
        hostingView = view
        mainView = view
    }
}
#endif
