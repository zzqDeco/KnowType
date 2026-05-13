#if canImport(InputMethodKit)
import AppKit
import InputMethodKit
import KnowTypeInputMethod

final class KnowTypeAppDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundle = Bundle.main
        let bundleIdentifier = bundle.bundleIdentifier ?? "com.knowtype.inputmethod.KnowType"
        let connectionName = bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String
            ?? "KnowType_Connection"
        server = IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier)
    }
}

let application = NSApplication.shared
let delegate = KnowTypeAppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
#else
import Foundation

fputs("KnowTypeInputMethodApp requires macOS InputMethodKit.\n", stderr)
exit(1)
#endif
