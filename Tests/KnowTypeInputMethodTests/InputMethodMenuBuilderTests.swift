#if canImport(AppKit)
import AppKit
import KnowTypeCore
import KnowTypeSettingsUI
@testable import KnowTypeInputMethod
import XCTest

@MainActor
final class InputMethodMenuBuilderTests: XCTestCase {
    func testDescriptorsMatchNativeInputMethodMenuOrder() {
        let descriptors = KnowTypeInputMethodMenuBuilder.descriptors(
            runtimePreferences: InputMethodRuntimePreferences(cloudContinuationEnabled: true)
        )

        XCTAssertEqual(
            descriptors.map(\.kind),
            [
                .aiContinuation,
                .separator,
                .openLogs,
                .openSupportFolder,
                .openRimeUserFolder,
                .separator,
                .settings,
                .about
            ]
        )
        XCTAssertEqual(descriptors[0].title, "AI Continuation")
        XCTAssertEqual(descriptors[0].stateRawValue, NSControl.StateValue.on.rawValue)
        XCTAssertEqual(descriptors[0].actionSelectorName, "toggleAIContinuation:")
        XCTAssertEqual(descriptors[6].title, "KnowType Settings...")
        XCTAssertEqual(descriptors[6].actionSelectorName, "showPreferences:")
        XCTAssertEqual(descriptors[6].keyEquivalent, "")
        XCTAssertEqual(descriptors.filter(\.isSeparator).count, 2)
    }

    func testMenuItemsUseExpectedSelectorsAndNoBareCharacterShortcut() throws {
        let menu = KnowTypeInputMethodMenuBuilder.makeMenu(
            target: NSObject(),
            runtimePreferences: InputMethodRuntimePreferences(cloudContinuationEnabled: false)
        )

        let titles = menu.items.map(\.title)
        XCTAssertEqual(
            titles,
            [
                "AI Continuation",
                "",
                "Open Logs...",
                "Open Support Folder...",
                "Open Rime User Folder...",
                "",
                "KnowType Settings...",
                "About KnowType..."
            ]
        )
        XCTAssertEqual(menu.items[0].state, .off)
        XCTAssertEqual(NSStringFromSelector(try XCTUnwrap(menu.items[0].action)), "toggleAIContinuation:")

        let settingsItem = try XCTUnwrap(menu.items.first { $0.title == "KnowType Settings..." })
        XCTAssertEqual(NSStringFromSelector(try XCTUnwrap(settingsItem.action)), "showPreferences:")
        XCTAssertEqual(settingsItem.keyEquivalent, "")
    }

    func testAIContinuationTogglePersistsRuntimePreference() throws {
        let suiteName = "KnowTypeInputMethodMenuBuilderTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsInputMethodRuntimePreferenceStore(defaults: defaults)
        try store.savePreferences(InputMethodRuntimePreferences(cloudContinuationEnabled: true))

        let preferences = try KnowTypeInputMethodMenuBuilder.toggleAIContinuation(in: store)

        XCTAssertFalse(preferences.cloudContinuationEnabled)
        XCTAssertFalse(store.loadPreferences().cloudContinuationEnabled)
    }

    func testPreferencesWindowUsesNativeSettingsWindowConfiguration() throws {
        let controller = KnowTypePreferencesWindowController()
        let window = try XCTUnwrap(controller.window)

        XCTAssertEqual(window.title, SettingsLocalization.string("settings.window.title"))
        XCTAssertGreaterThanOrEqual(window.minSize.width, 840)
        XCTAssertGreaterThanOrEqual(window.minSize.height, 560)
        XCTAssertEqual(window.tabbingMode, .disallowed)
        XCTAssertNotNil(window.contentView)
        if #available(macOS 11.0, *) {
            XCTAssertEqual(window.toolbarStyle, .unified)
        }
    }
}
#endif
