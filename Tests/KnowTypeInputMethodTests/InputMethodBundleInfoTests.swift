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
        XCTAssertTrue(script.contains("security find-identity -v -p codesigning"))
        XCTAssertTrue(script.contains("/Apple Development/"))
    }

    func testInputSourceScriptsUseDedicatedHelperExecutable() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let package = try String(contentsOf: rootURL.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(package.contains(#".executable(name: "knowtype-inputsource-tool""#))
        XCTAssertTrue(package.contains(#"name: "KnowTypeInputSourceTool""#))
        XCTAssertTrue(package.contains(#".linkedFramework("Carbon", .when(platforms: [.macOS]))"#))

        let scriptPaths = [
            "scripts/install-inputmethod.sh",
            "scripts/select-inputmethod.sh",
            "scripts/diagnose-inputmethod.sh",
            "scripts/create-local-system-policy-profile.sh",
            "scripts/smoke-inputmethod-install.sh",
            "scripts/lib/inputsource-tool.sh"
        ]
        let scripts = try scriptPaths
            .map { try String(contentsOf: rootURL.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")

        XCTAssertTrue(scripts.contains("knowtype-inputsource-tool"))
        XCTAssertTrue(scripts.contains("--no-diagnostic"))
        XCTAssertTrue(scripts.contains("--logs"))
        XCTAssertTrue(scripts.contains("GatekeeperPolicyScanError"))
        XCTAssertTrue(scripts.contains("com.apple.systempolicy.rule"))
        XCTAssertTrue(scripts.contains("codesign -dr -"))
        XCTAssertTrue(scripts.contains("PayloadIdentifier: com.knowtype.local.systempolicy"))
        XCTAssertTrue(scripts.contains("Rule PayloadType: com.apple.systempolicy.rule"))
        XCTAssertTrue(scripts.contains("Signing Identifier:"))
        XCTAssertTrue(scripts.contains("Team Identifier:"))
        XCTAssertTrue(scripts.contains("user-preference-write com.apple.inputsources"))
        XCTAssertFalse(scripts.contains("swift - <<'SWIFT'"))
        XCTAssertFalse(scripts.contains("swift - <<"))
    }

    func testInstallProfileSmokeValidatesMobileconfigWithoutSystemInstall() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let smokeScript = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/smoke-inputmethod-install.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(smokeScript.contains("create-local-system-policy-profile.sh"))
        XCTAssertTrue(smokeScript.contains(":PayloadIdentifier"))
        XCTAssertTrue(smokeScript.contains(":PayloadContent:0:PayloadIdentifier"))
        XCTAssertTrue(smokeScript.contains(":PayloadContent:0:PayloadType"))
        XCTAssertTrue(smokeScript.contains(":PayloadContent:0:OperationType"))
        XCTAssertTrue(smokeScript.contains(":PayloadContent:0:Requirement"))
        XCTAssertTrue(smokeScript.contains(":PayloadContent:0:Comment"))
        XCTAssertTrue(smokeScript.contains("codesign -dv"))
        XCTAssertTrue(smokeScript.contains("TeamIdentifier"))
        XCTAssertTrue(smokeScript.contains("Signature"))
        XCTAssertFalse(smokeScript.contains("profiles install"))
        XCTAssertFalse(smokeScript.contains("profiles -I"))
        XCTAssertFalse(smokeScript.contains("spctl --add"))
        XCTAssertFalse(smokeScript.contains("sudo "))
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
        XCTAssertTrue(helperSource.contains(#"knowtype-inputsource-tool dump"#))
        XCTAssertTrue(helperSource.contains(#"knowtype-inputsource-tool disable"#))
        XCTAssertTrue(helperSource.contains("mode.selectCapable"))
    }

    func testInputMethodAppSelfEnablesFromInstalledAppContext() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let appMain = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeInputMethodApp/main.swift"),
            encoding: .utf8
        )
        let installScript = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/install-inputmethod.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(appMain.contains("TextInputSourceActivation"))
        XCTAssertTrue(appMain.contains("TISRegisterInputSource"))
        XCTAssertTrue(appMain.contains("TISEnableInputSource"))
        XCTAssertTrue(appMain.contains("TISSelectInputSource"))
        XCTAssertTrue(appMain.contains("--knowtype-install-activate"))
        XCTAssertTrue(appMain.contains("input-method-app"))
        XCTAssertTrue(installScript.contains(#"open -n "$TARGET_PATH" --args --knowtype-install-activate"#))
        XCTAssertTrue(installScript.contains("pgrep -x KnowTypeInputMethodApp"))
        XCTAssertFalse(installScript.contains(#""$INPUTSOURCE_TOOL" register --path "$TARGET_PATH""#))
        XCTAssertFalse(installScript.contains(#""$INPUTSOURCE_TOOL" disable"#))
        XCTAssertFalse(installScript.contains(#""$INPUTSOURCE_TOOL" select"#))
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
        XCTAssertEqual(plist["LSHasLocalizedDisplayName"] as? Bool, true)
        XCTAssertNil(plist["LSUIElement"])
        XCTAssertEqual(plist["NSPrincipalClass"] as? String, "NSApplication")
        XCTAssertNil(plist["TISIconIsTemplate"])
        XCTAssertEqual(plist["TISIntendedLanguage"] as? String, "zh-Hans")
        XCTAssertEqual(plist["TISInputSourceID"] as? String, "com.knowtype.inputmethod.KnowType")
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "KnowTypeInputMethodIcon.icns")
        XCTAssertEqual(plist["tsInputMethodCharacterRepertoireKey"] as? [String], ["zh-Hans", "Latn"])

        let componentDict = try XCTUnwrap(plist["ComponentInputModeDict"] as? [String: Any])
        let modeList = try XCTUnwrap(componentDict["tsInputModeListKey"] as? [String: Any])
        let visibleModes = try XCTUnwrap(componentDict["tsVisibleInputModeOrderedArrayKey"] as? [String])
        let mode = try XCTUnwrap(modeList["com.knowtype.inputmethod.KnowType.Mode"] as? [String: Any])

        XCTAssertEqual(visibleModes, ["com.knowtype.inputmethod.KnowType.Mode"])
        XCTAssertNil(mode["TISIconLabels"])
        XCTAssertEqual(mode["TISInputSourceID"] as? String, "com.knowtype.inputmethod.KnowType.Mode")
        XCTAssertEqual(mode["TISIntendedLanguage"] as? String, "zh-Hans")
        XCTAssertEqual(mode["tsInputModeCharacterRepertoireKey"] as? [String], ["zh-Hans", "Latn"])
        XCTAssertEqual(mode["tsInputModeDefaultStateKey"] as? Bool, true)
        XCTAssertEqual(mode["tsInputModeIsVisibleKey"] as? Bool, true)
        XCTAssertEqual(mode["tsInputModeMenuIconFileKey"] as? String, "KnowTypeInputMethodIcon.tiff")
        XCTAssertEqual(mode["tsInputModeAlternateMenuIconFileKey"] as? String, "KnowTypeInputMethodIcon.tiff")
        XCTAssertEqual(mode["tsInputModePaletteIconFileKey"] as? String, "KnowTypeInputMethodIcon.tiff")
        XCTAssertEqual(mode["tsInputModePrimaryInScriptKey"] as? Bool, true)
        XCTAssertEqual(mode["tsInputModeScriptKey"] as? String, "smUnicodeScript")
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
