import Foundation
import XCTest

final class InputMethodBundleInfoTests: XCTestCase {
    func testBuildScriptPackagesSwiftPMResourceBundlesInsideAppResources() throws {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/build-inputmethod-bundle.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains(#""$BIN_DIR"/KnowType_*.bundle"#))
        XCTAssertTrue(script.contains(#"cp -R "$resource_bundle" "$CONTENTS_DIR/Resources/""#))
        XCTAssertTrue(script.contains(#"cp -R "$resource_path" "$CONTENTS_DIR/Resources/""#))
    }

    func testInputSourceScriptsUseDedicatedHelperExecutable() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let package = try String(contentsOf: rootURL.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(package.contains(#".executable(name: "knowtype-inputsource-tool""#))
        XCTAssertTrue(package.contains(#"name: "KnowTypeInputSourceTool""#))

        let scriptPaths = [
            "scripts/install-inputmethod.sh",
            "scripts/select-inputmethod.sh",
            "scripts/diagnose-inputmethod.sh",
            "scripts/lib/inputsource-tool.sh"
        ]
        let scripts = try scriptPaths
            .map { try String(contentsOf: rootURL.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")

        XCTAssertTrue(scripts.contains("knowtype-inputsource-tool"))
        XCTAssertTrue(scripts.contains("--no-diagnostic"))
        XCTAssertFalse(scripts.contains("swift - <<'SWIFT'"))
        XCTAssertFalse(scripts.contains("swift - <<"))
    }

    func testInputSourceHelperReportsHIToolboxPreferenceState() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let helperSource = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeInputSourceTool/main.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(helperSource.contains("AppleSelectedInputSources"))
        XCTAssertTrue(helperSource.contains("AppleEnabledInputSources"))
        XCTAssertTrue(helperSource.contains("preference.selected.knowtype"))
        XCTAssertTrue(helperSource.contains("preference.enabled.knowtype"))
    }

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
        XCTAssertEqual(plist["InputMethodConnectionName"] as? String, "com.knowtype.inputmethod.KnowType_Connection")
        XCTAssertEqual(plist["InputMethodServerControllerClass"] as? String, "KnowTypeInputController")
        XCTAssertEqual(plist["InputMethodServerDelegateClass"] as? String, "KnowTypeInputController")
        XCTAssertEqual(plist["LSBackgroundOnly"] as? Bool, true)
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
        XCTAssertEqual(mode["tsInputModeMenuIconFileKey"] as? String, "KnowTypeInputMethodIcon.tiff")
        XCTAssertEqual(mode["tsInputModePaletteIconFileKey"] as? String, "KnowTypeInputMethodIcon.tiff")
        XCTAssertEqual(mode["tsInputModePrimaryInScriptKey"] as? Bool, true)
        XCTAssertEqual(mode["tsInputModeScriptKey"] as? String, "smSimpChinese")
    }

    func testInputMethodProvidesLocalizedDisplayNames() throws {
        let resourcesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/InputMethod")

        let englishStrings = try String(
            contentsOf: resourcesURL.appendingPathComponent("en.lproj/InfoPlist.strings"),
            encoding: .utf8
        )
        let chineseStrings = try String(
            contentsOf: resourcesURL.appendingPathComponent("zh-Hans.lproj/InfoPlist.strings"),
            encoding: .utf8
        )

        XCTAssertTrue(englishStrings.contains(#""com.knowtype.inputmethod.KnowType.Mode" = "KnowType";"#))
        XCTAssertTrue(chineseStrings.contains(#""com.knowtype.inputmethod.KnowType.Mode" = "知键";"#))
        XCTAssertTrue(chineseStrings.contains(#""CFBundleDisplayName" = "知键";"#))
    }
}
