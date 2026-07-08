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
                .modeStatus,
                .separator,
                .openLogs,
                .openSupportFolder,
                .openRimeUserFolder,
                .separator,
                .settings,
                .about
            ]
        )
        XCTAssertEqual(descriptors[0].title, "AI 续写")
        XCTAssertEqual(descriptors[0].stateRawValue, NSControl.StateValue.on.rawValue)
        XCTAssertEqual(descriptors[0].actionSelectorName, "toggleAIContinuation:")
        XCTAssertEqual(descriptors[1].title, "中文输入 · 中文标点 · 半角")
        XCTAssertNil(descriptors[1].actionSelectorName)
        XCTAssertEqual(descriptors[7].title, "KnowType 设置...")
        XCTAssertEqual(descriptors[7].actionSelectorName, "showPreferences:")
        XCTAssertEqual(descriptors[7].keyEquivalent, "")
        XCTAssertEqual(descriptors.filter(\.isSeparator).count, 2)
    }

    func testDescriptorsCanShowAsciiEnglishFullWidthModeStatus() {
        let descriptors = KnowTypeInputMethodMenuBuilder.descriptors(
            runtimePreferences: InputMethodRuntimePreferences(),
            inputModeState: InputModeState(
                textMode: .ascii,
                punctuationMode: .english,
                symbolWidth: .fullWidth
            )
        )

        XCTAssertEqual(descriptors[1].kind, .modeStatus)
        XCTAssertEqual(descriptors[1].title, "ASCII 输入 · 英文标点 · 全角")
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
                "AI 续写",
                "中文输入 · 中文标点 · 半角",
                "",
                "打开日志...",
                "打开支持目录...",
                "打开 Rime 用户目录...",
                "",
                "KnowType 设置...",
                "关于 KnowType..."
            ]
        )
        XCTAssertEqual(menu.items[0].state, .off)
        XCTAssertEqual(NSStringFromSelector(try XCTUnwrap(menu.items[0].action)), "toggleAIContinuation:")
        XCTAssertFalse(menu.items[1].isEnabled)

        let settingsItem = try XCTUnwrap(menu.items.first { $0.title == "KnowType 设置..." })
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
