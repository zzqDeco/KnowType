import Foundation

#if canImport(AppKit)
import AppKit
import KnowTypeSettingsUI
import SwiftUI

@objc(KnowTypePreferencesWindowController)
public final class KnowTypePreferencesWindowController: NSWindowController {
    public convenience init() {
        self.init(window: Self.makeWindow())
    }

    public override init(window: NSWindow?) {
        super.init(window: window ?? Self.makeWindow())
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        window = Self.makeWindow()
    }

    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func makeWindow() -> NSWindow {
        let contentView = NSHostingView(
            rootView: KnowTypeSettingsRootView()
                .frame(minWidth: 840, minHeight: 560)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = SettingsLocalization.string("settings.window.title")
        window.minSize = NSSize(width: 840, height: 560)
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.tabbingMode = .disallowed
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unified
        }
        window.center()
        window.setFrameAutosaveName("KnowTypePreferencesWindow")
        return window
    }
}
#endif
