#if canImport(InputMethodKit)
import AppKit
import InputMethodKit

public final class KnowTypeIMKServerBootstrap {
    public let server: IMKServer?

    public init(name: String = "KnowType", bundleIdentifier: String) {
        self.server = IMKServer(name: name, bundleIdentifier: bundleIdentifier)
    }
}
#endif
