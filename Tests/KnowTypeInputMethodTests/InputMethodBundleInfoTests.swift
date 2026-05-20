import Foundation
import KnowTypeInputSourceSupport
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

    func testPreferencePaneBuildScriptPackagesSystemSettingsPane() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let package = try String(contentsOf: rootURL.appendingPathComponent("Package.swift"), encoding: .utf8)
        let script = try String(contentsOf: rootURL.appendingPathComponent("scripts/build-preference-pane.sh"), encoding: .utf8)
        let smokeScript = try String(contentsOf: rootURL.appendingPathComponent("scripts/smoke-inputmethod-install.sh"), encoding: .utf8)
        let diagnosticScript = try String(contentsOf: rootURL.appendingPathComponent("scripts/diagnose-inputmethod.sh"), encoding: .utf8)
        let inputControllerSource = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeInputMethod/InputController.swift"),
            encoding: .utf8
        )
        let source = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypePreferencePane/KnowTypePreferencePane.swift"),
            encoding: .utf8
        )
        let plistData = try Data(contentsOf: rootURL.appendingPathComponent("Resources/PreferencePane/Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        )

        XCTAssertTrue(package.contains(#".library(name: "KnowTypePreferencePane", type: .dynamic"#))
        XCTAssertTrue(package.contains(#".linkedFramework("PreferencePanes", .when(platforms: [.macOS]))"#))
        XCTAssertTrue(script.contains("--product KnowTypePreferencePane"))
        XCTAssertTrue(script.contains("libKnowTypePreferencePane.dylib"))
        XCTAssertTrue(script.contains("Frameworks"))
        XCTAssertTrue(script.contains("xcrun clang -bundle"))
        XCTAssertTrue(script.contains(#"-Wl,-rpath,@loader_path/../Frameworks"#))
        XCTAssertTrue(smokeScript.contains("Contents/Frameworks/libKnowTypePreferencePane.dylib"))
        XCTAssertTrue(smokeScript.contains("otool -hv"))
        XCTAssertTrue(smokeScript.contains("BUNDLE"))
        XCTAssertTrue(smokeScript.contains("bundle.principalClass"))
        XCTAssertTrue(diagnosticScript.contains("PreferencePane executable is a loadable bundle"))
        XCTAssertTrue(inputControllerSource.contains("override func showPreferences"))
        XCTAssertTrue(inputControllerSource.contains("KnowTypePreferencesWindowController()"))
        XCTAssertTrue(script.contains("KnowType.prefPane"))
        XCTAssertTrue(source.contains("override func loadMainView() -> NSView"))
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.knowtype.preferencepane")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "KnowTypePreferencePane")
        XCTAssertEqual(plist["NSPrincipalClass"] as? String, "KnowTypePreferencePane")
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "BNDL")
    }

    func testInputSourceScriptsUseDedicatedHelperExecutable() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let package = try String(contentsOf: rootURL.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(package.contains(#".executable(name: "knowtype-inputsource-tool""#))
        XCTAssertTrue(package.contains(#"name: "KnowTypeInputSourceTool""#))
        XCTAssertTrue(package.contains(#".library(name: "KnowTypeInputSourceSupport""#))
        XCTAssertTrue(package.contains(#"dependencies: ["KnowTypeInputSourceSupport"]"#))
        XCTAssertTrue(package.contains(#".linkedFramework("Carbon", .when(platforms: [.macOS]))"#))

        let scriptPaths = [
            "scripts/install-inputmethod.sh",
            "scripts/build-preference-pane.sh",
            "scripts/select-inputmethod.sh",
            "scripts/diagnose-inputmethod.sh",
            "scripts/repair-inputmethod-selection.sh",
            "scripts/create-local-system-policy-profile.sh",
            "scripts/smoke-inputmethod-install.sh",
            "scripts/lib/inputsource-ids.sh",
            "scripts/lib/inputsource-tool.sh"
        ]
        let scripts = try scriptPaths
            .map { try String(contentsOf: rootURL.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")

        XCTAssertTrue(scripts.contains("knowtype-inputsource-tool"))
        XCTAssertTrue(scripts.contains("KnowType.prefPane"))
        XCTAssertTrue(scripts.contains("~/Library/PreferencePanes"))
        XCTAssertTrue(scripts.contains("--no-diagnostic"))
        XCTAssertTrue(scripts.contains("--logs"))
        XCTAssertTrue(scripts.contains("GatekeeperPolicyScanError"))
        XCTAssertTrue(scripts.contains("com.apple.macl"))
        XCTAssertTrue(scripts.contains("com.apple.quarantine"))
        XCTAssertTrue(scripts.contains("Full Disk Access"))
        XCTAssertTrue(scripts.contains("lsregister"))
        XCTAssertFalse(scripts.contains("bootstrap --path"))
        XCTAssertTrue(scripts.contains("--knowtype-purge-legacy"))
        XCTAssertTrue(scripts.contains("strip_lsregister_suffix"))
        XCTAssertTrue(scripts.contains("expand_home_path"))
        XCTAssertTrue(scripts.contains(#"sub(/[[:space:]]*\(0x[[:xdigit:]]+\)$/, "", value)"#))
        XCTAssertTrue(scripts.contains("com.apple.systempolicy.rule"))
        XCTAssertTrue(scripts.contains("codesign -dr -"))
        XCTAssertTrue(scripts.contains("PayloadIdentifier: com.knowtype.local.systempolicy"))
        XCTAssertTrue(scripts.contains("Rule PayloadType: com.apple.systempolicy.rule"))
        XCTAssertTrue(scripts.contains("Requirement Source:"))
        XCTAssertTrue(scripts.contains("codesign CDHash fallback"))
        XCTAssertTrue(scripts.contains("Signing Identifier:"))
        XCTAssertTrue(scripts.contains("Team Identifier:"))
        XCTAssertTrue(scripts.contains("user-preference-write com.apple.inputsources"))
        XCTAssertTrue(scripts.contains("KNOWTYPE_ACTIVE_INPUT_MODE_ID=\"com.knowtype.inputmethod.KnowType.Hans\""))
        XCTAssertTrue(scripts.contains("KNOWTYPE_LEGACY_INPUT_MODE_IDS=(\"com.knowtype.inputmethod.KnowType.Mode\")"))
        XCTAssertTrue(scripts.contains("repair-preferences"))
        XCTAssertTrue(scripts.contains("KNOWTYPE_BUNDLE_BUILD_VERSION"))
        XCTAssertTrue(scripts.contains("open -g"))
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
        XCTAssertTrue(smokeScript.contains("build-preference-pane.sh"))
        XCTAssertTrue(smokeScript.contains(":NSPrincipalClass"))
        XCTAssertTrue(smokeScript.contains(":PayloadIdentifier"))
        XCTAssertTrue(smokeScript.contains(":PayloadContent:0:PayloadIdentifier"))
        XCTAssertTrue(smokeScript.contains(":PayloadContent:0:PayloadType"))
        XCTAssertTrue(smokeScript.contains(":PayloadContent:0:OperationType"))
        XCTAssertTrue(smokeScript.contains(":PayloadContent:0:Requirement"))
        XCTAssertTrue(smokeScript.contains(":PayloadContent:0:Comment"))
        XCTAssertTrue(smokeScript.contains("codesign -dv"))
        XCTAssertTrue(smokeScript.contains("CODESIGN_IDENTITY=-"))
        XCTAssertTrue(smokeScript.contains(#"sed -n 's/^# designated => //p'"#))
        XCTAssertTrue(smokeScript.contains(#"codesign -R "=$actual_requirement" -v "$bundle_path""#))
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
        XCTAssertTrue(helperSource.contains("AppleInputSourceHistory"))
        XCTAssertTrue(helperSource.contains("preference.selected.knowtype"))
        XCTAssertTrue(helperSource.contains("preference.enabled.knowtype"))
        XCTAssertTrue(helperSource.contains("preference.enabled.legacy.knowtype"))
        XCTAssertTrue(helperSource.contains("preference.history.knowtype"))
        XCTAssertTrue(helperSource.contains("preference.writes=skipped"))
        XCTAssertTrue(helperSource.contains(#"knowtype-inputsource-tool repair-preferences"#))
        XCTAssertTrue(helperSource.contains("preference.repair.active.mode.id"))
        XCTAssertTrue(helperSource.contains(#"knowtype-inputsource-tool inspect-preferences"#))
        XCTAssertTrue(helperSource.contains(#"knowtype-inputsource-tool dump"#))
        XCTAssertTrue(helperSource.contains(#"knowtype-inputsource-tool disable"#))
        XCTAssertTrue(helperSource.contains(#"knowtype-inputsource-tool dedupe-preferences"#))
        XCTAssertTrue(helperSource.contains(#"knowtype-inputsource-tool bootstrap"#))
        XCTAssertTrue(helperSource.contains(#"knowtype-inputsource-tool purge-legacy"#))
        XCTAssertTrue(helperSource.contains("AppleEnabledThirdPartyInputSources"))
        XCTAssertTrue(helperSource.contains("mode.selectCapable"))
        XCTAssertTrue(helperSource.contains("active.mode.count"))
        XCTAssertTrue(helperSource.contains("legacy.mode.count"))
        XCTAssertTrue(helperSource.contains("preference.thirdparty.enabled.knowtype"))
        XCTAssertTrue(helperSource.contains("preference.thirdparty.enabled.legacy.knowtype"))
        XCTAssertTrue(helperSource.contains("TISRegisterInputSource"))
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
        XCTAssertTrue(appMain.contains("--knowtype-switch-away"))
        XCTAssertTrue(appMain.contains("--knowtype-purge-legacy"))
        XCTAssertTrue(appMain.contains("--knowtype-disable-input-source"))
        XCTAssertTrue(appMain.contains("let explicitSelect"))
        XCTAssertTrue(appMain.contains("|| explicitSelect"))
        XCTAssertTrue(appMain.contains("input-method-app"))
        XCTAssertTrue(appMain.contains("KnowTypeInputSourceIDs.activeMode"))
        XCTAssertTrue(appMain.contains("sourceIsBetterActivationTarget"))
        XCTAssertTrue(appMain.contains("bestActivationTarget"))
        XCTAssertTrue(appMain.contains("sourceIsBetterSelectionTarget"))
        XCTAssertTrue(appMain.contains("bestSelectionTarget"))
        XCTAssertTrue(appMain.contains("bestSelectionTarget(inputSources(id: modeInputSourceID))"))
        XCTAssertTrue(appMain.contains("waitForCurrentInputSourceID(modeInputSourceID, timeout: 2.0)"))
        XCTAssertTrue(appMain.contains("inputSources(id: modeInputSourceID)"))
        XCTAssertTrue(appMain.contains("disableModesBeforeParent"))
        XCTAssertTrue(appMain.contains("kTISPropertyInputSourceIsEnableCapable"))
        XCTAssertTrue(appMain.contains("kTISPropertyInputSourceIsSelectCapable"))
        XCTAssertTrue(appMain.contains("enable.preference.writes=skipped"))
        XCTAssertTrue(appMain.contains("purge.legacy.preference.writes=skipped"))
        XCTAssertFalse(appMain.contains("CFPreferencesSetAppValue"))
        XCTAssertFalse(appMain.contains("AppleEnabledInputSources"))
        XCTAssertFalse(appMain.contains("AppleEnabledThirdPartyInputSources"))
        XCTAssertTrue(installScript.contains(#""$INSTALLED_EXECUTABLE" --knowtype-switch-away"#))
        XCTAssertTrue(installScript.contains("switch_away_before_replace"))
        XCTAssertTrue(installScript.contains("repair_preferences_best_effort"))
        XCTAssertTrue(installScript.contains("falling back to helper"))
        XCTAssertTrue(installScript.contains("continuing so installed app activation and diagnostics can run"))
        XCTAssertTrue(installScript.contains("scripts/lib/inputmethod-installation.sh"))
        XCTAssertTrue(installScript.contains("knowtype_remove_local_inputmethod_bundle_if_safe"))
        XCTAssertTrue(installScript.contains("knowtype_cleanup_local_duplicate_bundles_except"))
        XCTAssertTrue(installScript.contains("knowtype_unregister_launchservices_records_except"))
        XCTAssertTrue(installScript.contains("--dry-run"))
        XCTAssertLessThan(
            try XCTUnwrap(installScript.range(of: #"switch_away_before_replace"#, options: .backwards)?.lowerBound),
            try XCTUnwrap(installScript.range(of: #"killall KnowTypeInputMethodApp"#)?.lowerBound)
        )
        XCTAssertTrue(installScript.contains(#""$INSTALLED_EXECUTABLE" --knowtype-install-activate"#))
        XCTAssertTrue(installScript.contains(#""$INSTALLED_EXECUTABLE" --knowtype-purge-legacy"#))
        XCTAssertTrue(installScript.contains("pgrep -x KnowTypeInputMethodApp"))
        XCTAssertTrue(installScript.contains("knowtype_inputsource_tool"))
        XCTAssertTrue(installScript.contains("INPUTSOURCE_TOOL"))
        XCTAssertTrue(installScript.contains("--add-active"))
        XCTAssertFalse(installScript.contains(#""$INPUTSOURCE_TOOL" bootstrap --path "$TARGET_PATH""#))
        XCTAssertFalse(installScript.contains(#""$INPUTSOURCE_TOOL" register --path "$TARGET_PATH""#))
        XCTAssertFalse(installScript.contains(#""$INPUTSOURCE_TOOL" disable"#))
        XCTAssertFalse(installScript.contains(#""$INPUTSOURCE_TOOL" select"#))
    }

    func testInstallHelperUsesCurrentInputSourceIDsAndSafeRemoval() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let helperSource = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/lib/inputmethod-installation.sh"),
            encoding: .utf8
        )
        let uninstallScript = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/uninstall-inputmethod.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(helperSource.contains(#"source "$KNOWTYPE_INSTALLATION_LIB_DIR/inputsource-ids.sh""#))
        XCTAssertTrue(helperSource.contains("KNOWTYPE_ACTIVE_INPUT_MODE_ID"))
        XCTAssertTrue(helperSource.contains("KNOWTYPE_LEGACY_INPUT_MODE_IDS"))
        XCTAssertTrue(helperSource.contains(#"find "$target_dir" -maxdepth 1 \( -type d -o -type l \) -name '*.app'"#))
        XCTAssertTrue(helperSource.contains("refusing to remove or replace"))
        XCTAssertTrue(helperSource.contains("return 1"))
        XCTAssertTrue(uninstallScript.contains(#"elif (( DRY_RUN == 1 )); then"#))
        XCTAssertTrue(uninstallScript.contains("Would remove $bundle_count local KnowType input method bundle(s)."))
        XCTAssertTrue(uninstallScript.contains("Removed $bundle_count local KnowType input method bundle(s)."))
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

        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, KnowTypeInputSourceIDs.parent)
        XCTAssertEqual(plist["InputMethodConnectionName"] as? String, KnowTypeInputSourceIDs.connectionName)
        XCTAssertEqual(plist["InputMethodServerControllerClass"] as? String, "KnowTypeInputController")
        XCTAssertEqual(plist["InputMethodServerDelegateClass"] as? String, "KnowTypeInputController")
        XCTAssertEqual(plist["InputMethodServerPreferencesWindowControllerClass"] as? String, "KnowTypePreferencesWindowController")
        XCTAssertEqual(plist["LSBackgroundOnly"] as? Bool, false)
        XCTAssertEqual(plist["LSHasLocalizedDisplayName"] as? Bool, true)
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        XCTAssertEqual(plist["NSPrincipalClass"] as? String, "NSApplication")
        XCTAssertNil(plist["TISIconIsTemplate"])
        XCTAssertEqual(plist["TISIntendedLanguage"] as? String, "zh-Hans")
        XCTAssertEqual(plist["TISInputSourceID"] as? String, KnowTypeInputSourceIDs.parent)
        XCTAssertEqual(plist["TICapsLockLanguageSwitchCapable"] as? Bool, true)
        XCTAssertEqual(plist["TISParticipatesInTouchBar"] as? Bool, true)
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "KnowTypeInputMethodIcon.icns")
        XCTAssertEqual(plist["tsInputMethodCharacterRepertoireKey"] as? [String], ["Hans", "Hant", "Hani", "Hanb", "Han"])

        let component = try XCTUnwrap(plist["ComponentInputModeDict"] as? [String: Any])
        let modeList = try XCTUnwrap(component["tsInputModeListKey"] as? [String: Any])
        let mode = try XCTUnwrap(modeList[KnowTypeInputSourceIDs.activeMode] as? [String: Any])
        XCTAssertEqual(mode["TISInputSourceID"] as? String, KnowTypeInputSourceIDs.activeMode)
        XCTAssertEqual(mode["TISIntendedLanguage"] as? String, "zh-Hans")
        XCTAssertEqual(mode["tsInputModeCharacterRepertoireKey"] as? [String], ["Hans", "Hant", "Hani", "Hanb", "Han"])
        XCTAssertEqual(mode["tsInputModeIsVisibleKey"] as? Bool, true)
        XCTAssertEqual(mode["tsInputModeDefaultStateKey"] as? Bool, true)
        XCTAssertEqual(mode["tsInputModeKeyEquivalentKey"] as? String, "K")
        XCTAssertEqual(mode["tsInputModeKeyEquivalentModifiersKey"] as? Int, 4608)
        XCTAssertEqual(mode["tsInputModeScriptKey"] as? String, "smUnicodeScript")
        XCTAssertEqual(component["tsVisibleInputModeOrderedArrayKey"] as? [String], [KnowTypeInputSourceIDs.activeMode])
        XCTAssertEqual((plist["TISIconLabels"] as? [String: String])?["Primary"], "知")
        XCTAssertNotEqual(KnowTypeInputSourceIDs.activeMode, KnowTypeInputSourceIDs.parent)
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

        XCTAssertTrue(englishStrings.contains(#""com.knowtype.inputmethod.KnowType" = "KnowType";"#))
        XCTAssertTrue(englishStrings.contains(#""com.knowtype.inputmethod.KnowType.Hans" = "KnowType";"#))
        XCTAssertFalse(englishStrings.contains("com.knowtype.inputmethod.KnowType.Mode"))
        XCTAssertTrue(chineseStrings.contains(#""com.knowtype.inputmethod.KnowType" = "知键";"#))
        XCTAssertTrue(chineseStrings.contains(#""com.knowtype.inputmethod.KnowType.Hans" = "知键";"#))
        XCTAssertFalse(chineseStrings.contains("com.knowtype.inputmethod.KnowType.Mode"))
        XCTAssertTrue(chineseStrings.contains(#""CFBundleDisplayName" = "知键";"#))
    }

    func testInputSourceIdentifiersStayConsistentAcrossSwiftShellAndPlist() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let shellConstants = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/lib/inputsource-ids.sh"),
            encoding: .utf8
        )
        let plistData = try Data(contentsOf: rootURL.appendingPathComponent("Resources/InputMethod/Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        )
        XCTAssertTrue(shellConstants.contains("KNOWTYPE_PARENT_INPUT_SOURCE_ID=\"\(KnowTypeInputSourceIDs.parent)\""))
        XCTAssertTrue(shellConstants.contains("KNOWTYPE_ACTIVE_INPUT_MODE_ID=\"\(KnowTypeInputSourceIDs.activeMode)\""))
        XCTAssertTrue(shellConstants.contains("KNOWTYPE_INPUT_METHOD_CONNECTION_NAME=\"\(KnowTypeInputSourceIDs.connectionName)\""))
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, KnowTypeInputSourceIDs.parent)
        XCTAssertEqual(plist["TISInputSourceID"] as? String, KnowTypeInputSourceIDs.parent)
        XCTAssertEqual(plist["InputMethodConnectionName"] as? String, KnowTypeInputSourceIDs.connectionName)
        let component = try XCTUnwrap(plist["ComponentInputModeDict"] as? [String: Any])
        let modeList = try XCTUnwrap(component["tsInputModeListKey"] as? [String: Any])
        let mode = try XCTUnwrap(modeList[KnowTypeInputSourceIDs.activeMode] as? [String: Any])
        XCTAssertEqual(mode["TISInputSourceID"] as? String, KnowTypeInputSourceIDs.activeMode)
    }
}
