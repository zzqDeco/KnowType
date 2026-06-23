import Foundation
import KnowTypeInputSourceSupport
import XCTest

final class InputMethodBundleInfoTests: XCTestCase {
    func testBuildScriptPackagesSwiftPMResourceBundlesInsideAppResources() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/build-inputmethod-bundle.sh"),
            encoding: .utf8
        )
        let package = try String(contentsOf: rootURL.appendingPathComponent("Package.swift"), encoding: .utf8)

        XCTAssertTrue(script.contains(#""$BIN_DIR"/KnowType_*.bundle"#))
        XCTAssertTrue(script.contains(#"cp -R "$resource_bundle" "$CONTENTS_DIR/Resources/""#))
        XCTAssertTrue(script.contains(#"cp -R "$resource_path" "$CONTENTS_DIR/Resources/""#))
        XCTAssertTrue(smokeScriptContainsSettingsUIBundle(rootURL: rootURL))
        XCTAssertTrue(script.contains("security find-identity -v -p codesigning"))
        XCTAssertTrue(script.contains("/Apple Development/"))
        XCTAssertFalse(script.contains("install_name_tool"))
        XCTAssertTrue(script.contains("Required Rime rpath is missing"))
        XCTAssertTrue(package.contains(#""-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks""#))
    }

    func testRimeBridgeGuardsVersionedApiTailMembers() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/KnowTypeRimeBridge/KnowTypeRimeBridge.c")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("offsetof(RimeApi_stdbool, member)"))
        XCTAssertTrue(source.contains("sizeof(api->data_size) + (size_t)api->data_size"))
        XCTAssertTrue(source.contains("KTB_RIME_API_HAS(session->api, select_candidate_on_current_page)"))
        XCTAssertTrue(source.contains("KTB_RIME_API_HAS(session->api, select_candidate)"))
        XCTAssertTrue(source.contains("KTB_RIME_API_HAS(session->api, change_page)"))
        XCTAssertTrue(source.contains("KTB_RIME_API_HAS(session->api, get_current_schema)"))
        XCTAssertTrue(source.contains("KTB_RIME_API_HAS(session->api, get_status)"))
    }

    func testRimeBridgeUsesCurrentPageCandidatesForNativeSnapshots() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bridge = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeRimeBridge/KnowTypeRimeBridge.c"),
            encoding: .utf8
        )
        let engine = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeInputMethod/RimeConversionEngine.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(bridge.contains("candidate_list_begin(session->session_id"))
        XCTAssertFalse(bridge.contains("candidate_list_next(&iterator)"))
        XCTAssertFalse(bridge.contains("candidate_list_end(&iterator)"))
        XCTAssertFalse(bridge.contains("ktb_rime_copy_full_candidate_list"))
        XCTAssertFalse(bridge.contains("global_base_index"))
        XCTAssertTrue(bridge.contains("ktb_rime_copy_current_page_candidates(snapshot, &context.menu)"))
        XCTAssertTrue(bridge.contains("snapshot->candidates[index].index = (int)index"))
        XCTAssertTrue(engine.contains("case selectCandidate(Int)"))
        XCTAssertTrue(engine.contains("ktb_rime_select_candidate_on_current_page(session, max(0, index))"))
    }

    func testRimeArtifactPreparationPinsSharedDataRecipeCommits() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/prepare-rime-artifacts.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(script.contains("RIME_DATA_RECIPE_REFS"))
        XCTAssertTrue(script.contains("rime/rime-prelude=082425ea0684bca36474415d4a0e8db9b016487e"))
        XCTAssertTrue(script.contains("rime/rime-pinyin-simp=0c6861ef7420ee780270ca6d993d18d4101049d0"))
        XCTAssertTrue(script.contains("missing pinned ref for Rime recipe"))
        XCTAssertTrue(script.contains(#"git -C "$package_dir" fetch --depth 1 origin "$ref""#))
        XCTAssertTrue(script.contains("recipe_refs=${RIME_DATA_RECIPE_REFS}"))
    }

    func testCIWorkflowPreparesRimeArtifactsBeforeBuildTestAndSmoke() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let workflow = try String(
            contentsOf: rootURL.appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )

        let prepareRange = try XCTUnwrap(workflow.range(of: "./scripts/prepare-rime-artifacts.sh"))
        let buildRange = try XCTUnwrap(workflow.range(of: "swift build"))
        let testRange = try XCTUnwrap(workflow.range(of: "swift test"))
        let smokeRange = try XCTUnwrap(workflow.range(of: "./scripts/smoke-inputmethod-install.sh"))
        let prefpaneSmokeRange = try XCTUnwrap(workflow.range(of: "./scripts/smoke-inputmethod-install.sh --with-prefpane"))

        XCTAssertLessThan(prepareRange.lowerBound, buildRange.lowerBound)
        XCTAssertLessThan(prepareRange.lowerBound, testRange.lowerBound)
        XCTAssertLessThan(prepareRange.lowerBound, smokeRange.lowerBound)
        XCTAssertLessThan(prepareRange.lowerBound, prefpaneSmokeRange.lowerBound)
        XCTAssertLessThan(smokeRange.lowerBound, prefpaneSmokeRange.lowerBound)
    }

    func testRimeConversionBypassesNativeSessionForNonASCIIComposition() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let engine = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeInputMethod/RimeConversionEngine.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(engine.contains("nativeBypassUntilReset"))
        XCTAssertTrue(engine.contains("nativeRawInputMirror"))
        XCTAssertTrue(engine.contains("containsNonASCIIText"))
        XCTAssertTrue(engine.contains("processRawBypass"))
        XCTAssertTrue(engine.contains("rime-raw-bypass"))
        XCTAssertFalse(engine.contains("fallback.process(.text(existingComposition))"))
        XCTAssertFalse(engine.contains("guard scalar.isASCII else {\n                continue\n            }"))
    }

    func testRimeConversionReportsLiveSchemaForLexicalProfile() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let engine = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeInputMethod/RimeConversionEngine.swift"),
            encoding: .utf8
        )
        let bridge = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeRimeBridge/KnowTypeRimeBridge.c"),
            encoding: .utf8
        )
        let header = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeRimeBridge/include/KnowTypeRimeBridge.h"),
            encoding: .utf8
        )

        XCTAssertTrue(engine.contains("nativeSession?.currentSchemaID() ?? configuredSchemaID"))
        XCTAssertTrue(engine.contains("ktb_rime_copy_current_schema(session)"))
        XCTAssertTrue(bridge.contains("char *ktb_rime_copy_current_schema(KTBRimeSession *session)"))
        XCTAssertTrue(header.contains("char *ktb_rime_copy_current_schema(KTBRimeSession *session);"))
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
        XCTAssertTrue(script.contains(#"copy_swiftpm_resource_bundle "KnowType_KnowTypeSettingsUI.bundle""#))
        XCTAssertTrue(script.contains(#"copy_swiftpm_resource_bundle "KnowType_KnowTypeCore.bundle""#))
        XCTAssertTrue(script.contains("xcrun clang -bundle"))
        XCTAssertTrue(script.contains(#"-Wl,-rpath,@loader_path/../Frameworks"#))
        XCTAssertTrue(smokeScript.contains("Contents/Frameworks/libKnowTypePreferencePane.dylib"))
        XCTAssertTrue(smokeScript.contains("Contents/Resources/KnowType_KnowTypeSettingsUI.bundle"))
        XCTAssertTrue(smokeScript.contains("assert_file_any \"zh-Hans settings localization\""))
        XCTAssertTrue(smokeScript.contains("zh-Hans.lproj/Localizable.strings"))
        XCTAssertTrue(smokeScript.contains("zh-hans.lproj/Localizable.strings"))
        XCTAssertTrue(diagnosticScript.contains("PreferencePane settings UI resource bundle is packaged"))
        XCTAssertTrue(smokeScript.contains("--with-prefpane"))
        XCTAssertTrue(smokeScript.contains("WITH_PREFPANE=0"))
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

    private func smokeScriptContainsSettingsUIBundle(rootURL: URL) -> Bool {
        guard let smokeScript = try? String(
            contentsOf: rootURL.appendingPathComponent("scripts/smoke-inputmethod-install.sh"),
            encoding: .utf8
        ) else {
            return false
        }
        return smokeScript.contains("Contents/Resources/KnowType_KnowTypeSettingsUI.bundle")
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
            "scripts/lib/inputmethod-installation.sh",
            "scripts/lib/inputsource-tool.sh"
        ]
        let scripts = try scriptPaths
            .map { try String(contentsOf: rootURL.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")

        XCTAssertTrue(scripts.contains("knowtype-inputsource-tool"))
        XCTAssertTrue(scripts.contains("KnowType.prefPane"))
        XCTAssertTrue(scripts.contains("Library/PreferencePanes"))
        XCTAssertTrue(scripts.contains("com.apple.preferencepanes.usercache"))
        XCTAssertTrue(scripts.contains("com.apple.systemsettings.menucache"))
        XCTAssertTrue(scripts.contains("KNOWTYPE_PREFPANE_CACHE_PATHS"))
        XCTAssertTrue(scripts.contains("knowtype_clean_preferencepane_caches"))
        XCTAssertTrue(scripts.contains("System Settings PreferencePane caches still contain stale KnowType prefPane metadata"))
        XCTAssertTrue(scripts.contains("--no-diagnostic"))
        XCTAssertTrue(scripts.contains("--logs"))
        XCTAssertTrue(scripts.contains("GatekeeperPolicyScanError"))
        XCTAssertTrue(scripts.contains("com.apple.macl"))
        XCTAssertTrue(scripts.contains("com.apple.quarantine"))
        XCTAssertTrue(scripts.contains("Full Disk Access"))
        XCTAssertTrue(scripts.contains("lsregister"))
        XCTAssertTrue(scripts.contains("bootstrap"))
        XCTAssertTrue(scripts.contains("purge-legacy"))
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
        XCTAssertTrue(scripts.contains("KNOWTYPE_ACTIVE_INPUT_MODE_ID=\"com.knowtype.inputmethod.KnowType\""))
        XCTAssertTrue(scripts.contains("KNOWTYPE_LEGACY_INPUT_MODE_IDS=(\"com.knowtype.inputmethod.KnowType.Hans\" \"com.knowtype.inputmethod.KnowType.Mode\")"))
        XCTAssertTrue(scripts.contains("repair-preferences"))
        XCTAssertTrue(scripts.contains("KNOWTYPE_BUNDLE_BUILD_VERSION"))
        XCTAssertTrue(scripts.contains("launching the input method host"))
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

    func testReleasePackageDoesNotIncludeStandaloneSettingsApp() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let packageScript = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/package-release.sh"),
            encoding: .utf8
        )
        let dmgScript = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/package-dmg.sh"),
            encoding: .utf8
        )
        let releaseWorkflow = try String(
            contentsOf: rootURL.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        XCTAssertFalse(packageScript.contains("KnowType Settings.app"))
        XCTAssertTrue(packageScript.contains("compatibility KnowType.prefPane"))
        XCTAssertTrue(packageScript.contains(#"shasum -a 256 "$(basename "$archive_path")""#))
        XCTAssertTrue(dmgScript.contains("Developer Preview DMG"))
        XCTAssertTrue(dmgScript.contains("Install KnowType.command"))
        XCTAssertTrue(dmgScript.contains("--from-dmg-payload"))
        XCTAssertTrue(dmgScript.contains(#"shasum -a 256 "$(basename "$dmg_path")""#))
        XCTAssertTrue(releaseWorkflow.contains("./scripts/package-dmg.sh"))
        XCTAssertTrue(releaseWorkflow.contains("macos-dev-preview.dmg"))
        XCTAssertTrue(releaseWorkflow.contains("./scripts/smoke-inputmethod-install.sh --with-prefpane"))
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
        XCTAssertTrue(helperSource.contains("repairSelectedPreferenceAwayFromKnowType"))
        XCTAssertTrue(helperSource.contains("switch-away.preference.selected.changed"))
        XCTAssertTrue(helperSource.contains("kTISNotifySelectedKeyboardInputSourceChanged"))
        XCTAssertTrue(helperSource.contains("preference.repair.active.mode.id"))
        XCTAssertTrue(helperSource.contains(#"key: "AppleSelectedInputSources""#))
        XCTAssertTrue(helperSource.contains("bootstrap.parent.enabled"))
        XCTAssertTrue(helperSource.contains("bootstrap.mode.enabled"))
        XCTAssertTrue(helperSource.contains("if selectStatus != noErr"))
        XCTAssertTrue(helperSource.contains("--include-selected"))
        XCTAssertTrue(helperSource.contains("--remove-parent-anchor"))
        XCTAssertTrue(helperSource.contains("preference.repair.include.selected"))
        XCTAssertTrue(helperSource.contains("preference.repair.remove.parent.anchor"))
        XCTAssertTrue(helperSource.contains("activePlacement: .prepend"))
        XCTAssertTrue(helperSource.contains("case .prepend:"))
        XCTAssertTrue(helperSource.contains("removeEnabledParentAnchor = removeParentAnchor && !addActive"))
        XCTAssertNotNil(helperSource.range(
            of: #"key:\s*"AppleEnabledInputSources"[\s\S]*?removeParent:\s*removeEnabledParentAnchor"#,
            options: .regularExpression
        ))
        XCTAssertNotNil(helperSource.range(
            of: #"key:\s*"AppleEnabledThirdPartyInputSources"[\s\S]*?removeParent:\s*removeEnabledParentAnchor"#,
            options: .regularExpression
        ))
        XCTAssertNotNil(helperSource.range(
            of: #"key:\s*"AppleInputSourceHistory"[\s\S]*?activePlacement:\s*includeSelected\s*\?\s*\.prepend\s*:\s*\.afterFirstRetained"#,
            options: .regularExpression
        ))
        XCTAssertNotNil(helperSource.range(
            of: #"key:\s*"AppleSelectedInputSources"[\s\S]*?activePlacement:\s*\.prepend"#,
            options: .regularExpression
        ))
        XCTAssertNotNil(helperSource.range(
            of: #"if\s+includeSelected\s*\{[\s\S]*?postTISNotification\(kTISNotifySelectedKeyboardInputSourceChanged\)"#,
            options: .regularExpression
        ))
        XCTAssertTrue(helperSource.contains("bootstrap.singleSource"))
        XCTAssertTrue(helperSource.contains("if !parentEnabled || !modeEnabled"))
        XCTAssertTrue(helperSource.contains(#"knowtype-inputsource-tool inspect-preferences"#))
        XCTAssertTrue(helperSource.contains(#"knowtype-inputsource-tool dump"#))
        XCTAssertTrue(helperSource.contains(#"knowtype-inputsource-tool disable"#))
        XCTAssertTrue(helperSource.contains(#"knowtype-inputsource-tool dedupe-preferences"#))
        XCTAssertTrue(helperSource.contains(#"knowtype-inputsource-tool bootstrap"#))
        XCTAssertTrue(helperSource.contains(#"knowtype-inputsource-tool purge-legacy"#))
        XCTAssertTrue(helperSource.contains("AppleEnabledThirdPartyInputSources"))
        XCTAssertTrue(helperSource.contains("mode.selectCapable"))
        XCTAssertTrue(helperSource.contains("user.visible.mode.count"))
        XCTAssertTrue(helperSource.contains("inputSource.singleSource"))
        XCTAssertTrue(helperSource.contains("parentSources + modeSources + legacySourcesByID.flatMap"))
        XCTAssertTrue(helperSource.contains("boolProperty(source, kTISPropertyInputSourceIsEnabled) &&"))
        XCTAssertTrue(helperSource.contains("kTISPropertyInputSourceIsSelectCapable"))
        XCTAssertTrue(helperSource.contains("active.mode.count"))
        XCTAssertTrue(helperSource.contains("legacy.mode.count"))
        XCTAssertTrue(helperSource.contains("preference.thirdparty.enabled.knowtype"))
        XCTAssertTrue(helperSource.contains("preference.thirdparty.enabled.parent.knowtype"))
        XCTAssertTrue(helperSource.contains("preference.thirdparty.enabled.legacy.knowtype"))
        XCTAssertTrue(helperSource.contains("--legacy-parent-anchor"))
        XCTAssertTrue(helperSource.contains("preference.repair.add.parent.anchor"))
        XCTAssertTrue(helperSource.contains("preference.repair.add.legacy.parent.anchor"))
        XCTAssertTrue(helperSource.contains("preference.repair.legacy.parent.anchor.option"))
        XCTAssertTrue(helperSource.contains("enableInputSource(parent, label: \"parent\")"))
        XCTAssertTrue(helperSource.contains("enableInputSource(mode, label: \"mode\")"))
        XCTAssertTrue(helperSource.contains("exitOnFailure: false"))
        XCTAssertTrue(helperSource.contains("requireSelected: true"))
        XCTAssertTrue(helperSource.contains("return OSStatus(paramErr)"))
        XCTAssertFalse(helperSource.contains("preferencesContainInputModeOrParent"))
        XCTAssertFalse(helperSource.contains("removeParent: !addLegacyParentAnchor"))
        XCTAssertFalse(helperSource.contains("addParent: addActive && addLegacyParentAnchor"))
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
        let diagnosticScript = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/diagnose-inputmethod.sh"),
            encoding: .utf8
        )
        let rollbackScript = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/rollback-inputmethod.sh"),
            encoding: .utf8
        )
        let repairScript = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/repair-inputmethod-selection.sh"),
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
        XCTAssertTrue(appMain.contains("bestSelectionTarget(inputSources(id: activeInputSourceID))"))
        XCTAssertTrue(appMain.contains("waitForCurrentInputSourceID(activeInputSourceID, timeout: 2.0)"))
        XCTAssertTrue(appMain.contains("inputSources(id: activeInputSourceID)"))
        XCTAssertTrue(appMain.contains("usesSingleInputSource"))
        XCTAssertTrue(appMain.contains("disableModesBeforeParent"))
        XCTAssertTrue(appMain.contains(".sorted(by: enableParentBeforeModes)"))
        XCTAssertTrue(appMain.contains("parentAnchorReady && modeReady"))
        XCTAssertTrue(appMain.contains("enable.parent.ready"))
        XCTAssertTrue(appMain.contains("enable.mode.ready"))
        XCTAssertTrue(appMain.contains("kTISPropertyInputSourceIsEnableCapable"))
        XCTAssertTrue(appMain.contains("kTISPropertyInputSourceIsSelectCapable"))
        XCTAssertTrue(appMain.contains("enable.preference.writes=skipped"))
        XCTAssertTrue(appMain.contains("purge.legacy.preference.writes=skipped"))
        XCTAssertFalse(appMain.contains("CFPreferencesSetAppValue"))
        XCTAssertFalse(appMain.contains("AppleEnabledInputSources"))
        XCTAssertFalse(appMain.contains("AppleEnabledThirdPartyInputSources"))
        XCTAssertTrue(installScript.contains("switch_away_before_replace"))
        XCTAssertTrue(installScript.contains("repair_preferences_best_effort"))
        XCTAssertTrue(installScript.contains("purge_legacy_best_effort"))
        XCTAssertTrue(installScript.contains("bootstrap_input_source_best_effort"))
        XCTAssertTrue(installScript.contains("switch-away"))
        XCTAssertTrue(installScript.contains(#""$tool" "${args[@]}""#))
        XCTAssertTrue(installScript.contains(#""$tool" purge-legacy"#))
        XCTAssertTrue(installScript.contains(#""$tool" bootstrap"#))
        XCTAssertTrue(installScript.contains(#"--path "$TARGET_PATH""#))
        XCTAssertTrue(installScript.contains("launching the input method host"))
        XCTAssertTrue(installScript.contains("continuing so diagnostics can run"))
        XCTAssertFalse(installScript.contains("--include-selected"))
        XCTAssertFalse(installScript.contains("--remove-parent-anchor"))
        XCTAssertFalse(rollbackScript.contains("--include-selected"))
        XCTAssertFalse(rollbackScript.contains("--remove-parent-anchor"))
        XCTAssertTrue(repairScript.contains("--include-selected"))
        XCTAssertTrue(repairScript.contains("repair_args+=(--include-selected)"))
        XCTAssertTrue(repairScript.contains("if (( bootstrap_select_status == 0 ))"))
        XCTAssertTrue(repairScript.contains("selected preferences were not rewritten"))
        XCTAssertTrue(installScript.contains("SCRIPT_DIR="))
        XCTAssertTrue(installScript.contains("SCRIPTS_DIR=\"$SCRIPT_DIR\""))
        XCTAssertTrue(installScript.contains(#"source "$SCRIPTS_DIR/lib/inputmethod-installation.sh""#))
        XCTAssertTrue(installScript.contains("knowtype_remove_local_inputmethod_bundle_if_safe"))
        XCTAssertTrue(installScript.contains("knowtype_cleanup_local_duplicate_bundles_except"))
        XCTAssertTrue(installScript.contains("knowtype_unregister_launchservices_records_except"))
        XCTAssertTrue(installScript.contains("--dry-run"))
        XCTAssertTrue(installScript.contains("require_input_method_host_stopped"))
        XCTAssertTrue(installScript.contains("process shutdown can flush Rime user data"))
        XCTAssertFalse(installScript.contains("killall KnowTypeInputMethodApp"))
        XCTAssertFalse(installScript.contains(#""$INSTALLED_EXECUTABLE" --knowtype-switch-away"#))
        XCTAssertFalse(installScript.contains(#""$INSTALLED_EXECUTABLE" --knowtype-install-activate"#))
        XCTAssertFalse(installScript.contains(#""$INSTALLED_EXECUTABLE" --knowtype-purge-legacy"#))
        XCTAssertFalse(installScript.contains(#"open -g "$TARGET_PATH""#))
        XCTAssertTrue(installScript.contains("knowtype_input_method_host_is_running"))
        XCTAssertTrue(installScript.contains("ps -axo command="))
        XCTAssertTrue(installScript.contains(#"*/KnowTypeInputMethodApp\ *"#))
        XCTAssertFalse(installScript.contains(#"${command%% *}"#))
        XCTAssertFalse(installScript.contains("pgrep -x KnowTypeInputMethodApp"))
        XCTAssertTrue(installScript.contains("knowtype_inputsource_tool"))
        XCTAssertTrue(installScript.contains("INPUTSOURCE_TOOL"))
        XCTAssertTrue(installScript.contains("--with-prefpane"))
        XCTAssertTrue(installScript.contains("KNOWTYPE_INSTALL_PREFPANE"))
        XCTAssertTrue(installScript.contains("KnowType settings are available from the input-method menu"))
        XCTAssertTrue(installScript.contains(#""$SCRIPTS_DIR/diagnose-inputmethod.sh" --json --path "$TARGET_PATH""#))
        XCTAssertFalse(installScript.contains(#""$SCRIPTS_DIR/diagnose-inputmethod.sh" --strict --path "$TARGET_PATH""#))
        XCTAssertTrue(installScript.contains(#"data.get("failures")"#))
        XCTAssertTrue(installScript.contains("Postflight uses the JSON install snapshot only"))
        XCTAssertTrue(installScript.contains("Stale compatibility PreferencePane that would be removed"))
        XCTAssertTrue(installScript.contains("REMOVED_STALE_PREFPANE=1"))
        XCTAssertTrue(installScript.contains("Removed stale KnowType compatibility PreferencePane"))
        XCTAssertTrue(installScript.contains("--add-active"))
        XCTAssertFalse(installScript.contains("--legacy-parent-anchor"))
        XCTAssertTrue(diagnosticScript.contains("ALLOW_LEGACY_PARENT_ANCHOR=0"))
        XCTAssertTrue(diagnosticScript.contains("--legacy-parent-anchor"))
        XCTAssertTrue(diagnosticScript.contains("single input source model"))
        XCTAssertTrue(diagnosticScript.contains("active KnowType input source"))
        XCTAssertFalse(diagnosticScript.contains("Parent enabled anchors are normal"))
        XCTAssertFalse(diagnosticScript.contains("required KnowType parent anchor"))
        XCTAssertFalse(installScript.contains(#""$INPUTSOURCE_TOOL" register --path "$TARGET_PATH""#))
        XCTAssertFalse(installScript.contains(#""$INPUTSOURCE_TOOL" disable"#))
        XCTAssertFalse(installScript.contains(#""$INPUTSOURCE_TOOL" select"#))
        XCTAssertTrue(rollbackScript.contains(#""$inputsource_tool" purge-legacy"#))
        XCTAssertTrue(rollbackScript.contains(#""$inputsource_tool" bootstrap"#))
        XCTAssertTrue(rollbackScript.contains("require_input_method_host_stopped"))
        XCTAssertTrue(rollbackScript.contains("process shutdown can flush Rime user data"))
        XCTAssertTrue(rollbackScript.contains("knowtype_input_method_host_is_running"))
        XCTAssertTrue(rollbackScript.contains("ps -axo command="))
        XCTAssertTrue(rollbackScript.contains(#"*/KnowTypeInputMethodApp\ *"#))
        XCTAssertFalse(rollbackScript.contains(#"${command%% *}"#))
        XCTAssertFalse(rollbackScript.contains("pgrep -x KnowTypeInputMethodApp"))
        XCTAssertFalse(rollbackScript.contains(#"KnowTypeInputMethodApp" --knowtype-purge-legacy"#))
        XCTAssertFalse(rollbackScript.contains("killall KnowTypeInputMethodApp"))
        XCTAssertFalse(rollbackScript.contains(#"open -g "$target_path""#))
        XCTAssertTrue(repairScript.contains(#""$INPUTSOURCE_TOOL" purge-legacy"#))
        XCTAssertTrue(repairScript.contains(#""$INPUTSOURCE_TOOL" bootstrap"#))
        XCTAssertTrue(repairScript.contains(#"--select"#))
        XCTAssertTrue(repairScript.contains("single user-selectable KnowType input source"))
        XCTAssertTrue(repairScript.contains("continuing with enabled/history repair, menu refresh, and diagnostics"))
        XCTAssertTrue(repairScript.contains("selected preferences were not rewritten because helper-local selection failed"))
        XCTAssertFalse(repairScript.contains("--legacy-parent-anchor"))
        XCTAssertFalse(repairScript.contains(#""$BUNDLE_EXECUTABLE" --knowtype-install-activate"#))
        XCTAssertFalse(repairScript.contains(#""$BUNDLE_EXECUTABLE" --knowtype-purge-legacy"#))
        XCTAssertFalse(repairScript.contains("killall KnowTypeInputMethodApp"))
        XCTAssertFalse(repairScript.contains(#"open -g "$BUNDLE_PATH""#))
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
        XCTAssertTrue(uninstallScript.contains("optional compatibility KnowType PreferencePane"))
        XCTAssertTrue(uninstallScript.contains("--remove-parent-anchor"))
        XCTAssertTrue(uninstallScript.contains(#"elif (( DRY_RUN == 1 )); then"#))
        XCTAssertTrue(uninstallScript.contains("Would remove $bundle_count local KnowType input method bundle(s)."))
        XCTAssertTrue(uninstallScript.contains("Removed $bundle_count local KnowType input method bundle(s)."))
    }

    func testInputMethodInfoDeclaresSingleInputSource() throws {
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

        XCTAssertNil(plist["ComponentInputModeDict"])
        XCTAssertEqual((plist["TISIconLabels"] as? [String: String])?["Primary"], "知")
        XCTAssertEqual(KnowTypeInputSourceIDs.activeMode, KnowTypeInputSourceIDs.parent)
        XCTAssertTrue(KnowTypeInputSourceIDs.legacyModes.contains("com.knowtype.inputmethod.KnowType.Hans"))
        XCTAssertTrue(KnowTypeInputSourceIDs.legacyModes.contains("com.knowtype.inputmethod.KnowType.Mode"))
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
        XCTAssertFalse(englishStrings.contains("com.knowtype.inputmethod.KnowType.Hans"))
        XCTAssertFalse(englishStrings.contains("com.knowtype.inputmethod.KnowType.Mode"))
        XCTAssertTrue(chineseStrings.contains(#""com.knowtype.inputmethod.KnowType" = "知键";"#))
        XCTAssertFalse(chineseStrings.contains("com.knowtype.inputmethod.KnowType.Hans"))
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
        XCTAssertNil(plist["ComponentInputModeDict"])
        XCTAssertEqual(KnowTypeInputSourceIDs.activeMode, KnowTypeInputSourceIDs.parent)
    }

    func testDiagnoseJsonSkipsMalformedAcceptedFeedbackRows() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-diagnose-feedback-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: testRoot)
        }

        let home = testRoot.appendingPathComponent("Home", isDirectory: true)
        let bundle = testRoot.appendingPathComponent("KnowType.app", isDirectory: true)
        let aiDirectory = home
            .appendingPathComponent("Library/Application Support/KnowType/AI", isDirectory: true)
        try FileManager.default.createDirectory(at: aiDirectory, withIntermediateDirectories: true)
        try makeMinimalBundle(at: bundle)

        try Data(
            """
            ["not", "a feedback record"]
            {"acceptID":"22222222-2222-2222-2222-222222222222","acceptedTextHash":"abc","deletedRanges":[],"deletedTexts":[],"deletedRatio":"bad","strength":"strong"}
            {"acceptID":"11111111-1111-1111-1111-111111111111","acceptedTextHash":"abc","deletedRanges":[{"location":1,"length":1}],"deletedTexts":["x"],"deletedVisibleCharacterCount":1,"deletedRatio":0.5,"strength":"strong","reason":"delete_idle"}

            """.utf8
        ).write(to: aiDirectory.appendingPathComponent("accepted-ai-feedback.jsonl"))

        let output = try runDiagnoseJSON(
            scriptURL: rootURL.appendingPathComponent("scripts/diagnose-inputmethod.sh"),
            homeURL: home,
            bundleURL: bundle
        )
        let snapshot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: output) as? [String: Any]
        )
        let userData = try XCTUnwrap(snapshot["userData"] as? [String: Any])
        let acceptedLearning = try XCTUnwrap(userData["acceptedLearning"] as? [String: Any])
        let feedback = try XCTUnwrap(acceptedLearning["feedback"] as? [String: Any])
        let feedbackHistory = try XCTUnwrap(feedback["history"] as? [String: Any])
        let warnings = try XCTUnwrap(acceptedLearning["warnings"] as? [String])

        XCTAssertEqual(feedbackHistory["recordCount"] as? Int, 1)
        XCTAssertTrue(warnings.contains("invalid_feedback_history_lines:2"))
    }

    private func makeMinimalBundle(at bundle: URL) throws {
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        let executable = contents.appendingPathComponent("MacOS/KnowTypeInputMethodApp", isDirectory: false)
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("Frameworks", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("Resources/rime-data", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: executable)
        try Data().write(to: contents.appendingPathComponent("Frameworks/librime.1.dylib"))
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.knowtype.inputmethod.KnowType",
            "CFBundleShortVersionString": "0.0.0-test",
            "CFBundleVersion": "1"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    private func runDiagnoseJSON(
        scriptURL: URL,
        homeURL: URL,
        bundleURL: URL
    ) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, "--json", "--path", bundleURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = homeURL.path
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail("diagnose-inputmethod.sh --json failed: \(stderr)")
        }
        return data
    }
}
