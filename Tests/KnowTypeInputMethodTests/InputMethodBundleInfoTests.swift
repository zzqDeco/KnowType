import Foundation
import XCTest

final class InputMethodBundleInfoTests: XCTestCase {
    func testInputMethodInfoDeclaresVisibleInputMode() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/InputMethod/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.knowtype.inputmethod.KnowType")
        XCTAssertEqual(plist["InputMethodConnectionName"] as? String, "KnowType_Connection")
        XCTAssertEqual(plist["InputMethodServerControllerClass"] as? String, "KnowTypeInputController")
        XCTAssertEqual(plist["InputMethodServerDelegateClass"] as? String, "KnowTypeInputController")
        XCTAssertNil(plist["LSBackgroundOnly"])
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        XCTAssertEqual(plist["NSPrincipalClass"] as? String, "NSApplication")
        XCTAssertEqual(plist["TISIntendedLanguage"] as? String, "zh-Hans")
        XCTAssertEqual(plist["TISInputSourceID"] as? String, "com.knowtype.inputmethod.KnowType")
        XCTAssertEqual(plist["tsInputMethodCharacterRepertoireKey"] as? [String], ["Hans", "Latn"])

        let componentDict = try XCTUnwrap(plist["ComponentInputModeDict"] as? [String: Any])
        let modeList = try XCTUnwrap(componentDict["tsInputModeListKey"] as? [String: Any])
        let visibleModes = try XCTUnwrap(componentDict["tsVisibleInputModeOrderedArrayKey"] as? [String])
        let mode = try XCTUnwrap(modeList["com.knowtype.inputmethod.KnowType.Mode"] as? [String: Any])

        XCTAssertEqual(visibleModes, ["com.knowtype.inputmethod.KnowType.Mode"])
        XCTAssertEqual(mode["TISInputSourceID"] as? String, "com.knowtype.inputmethod.KnowType.Mode")
        XCTAssertEqual(mode["TISIntendedLanguage"] as? String, "zh-Hans")
        XCTAssertEqual(mode["tsInputModeCharacterRepertoireKey"] as? [String], ["Hans", "Latn"])
        XCTAssertEqual(mode["tsInputModeDefaultStateKey"] as? Bool, true)
        XCTAssertEqual(mode["tsInputModeIsVisibleKey"] as? Bool, true)
        XCTAssertEqual(mode["tsInputModeMenuIconFileKey"] as? String, "KnowTypeInputMethodIcon.icns")
        XCTAssertEqual(mode["tsInputModePaletteIconFileKey"] as? String, "KnowTypeInputMethodIcon.icns")
        XCTAssertEqual(mode["tsInputModePrimaryInScriptKey"] as? Bool, true)
        XCTAssertEqual(mode["tsInputModeScriptKey"] as? String, "smSimpChinese")
    }
}
