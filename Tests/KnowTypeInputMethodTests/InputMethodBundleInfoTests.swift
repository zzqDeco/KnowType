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
        XCTAssertTrue(source.contains("KTB_RIME_API_HAS(session->api, set_option)"))
        XCTAssertTrue(source.contains("KTB_RIME_API_HAS(session->api, get_option)"))
        XCTAssertTrue(source.contains("!session->api->set_option"))
        XCTAssertTrue(source.contains("!session->api->get_option"))
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
        XCTAssertTrue(package.contains(#"dependencies: ["KnowTypeInputSourceSupport", "KnowTypeProviders"]"#))
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

        let selectScript = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/select-inputmethod.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(selectScript.contains(#"knowtype_inputsource_tool "$ROOT_DIR""#))
        XCTAssertTrue(selectScript.contains(#""$INPUTSOURCE_TOOL" "${bootstrap_args[@]}""#))
        XCTAssertFalse(selectScript.contains(#"KnowTypeInputMethodApp" --knowtype-register-input-source"#))

        let helperMain = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeInputSourceTool/main.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(helperMain.contains("requireSelected: requireSelected"))
        XCTAssertTrue(helperMain.contains("TISSupport.bestActivationTarget(TISSupport.inputSources(id: parentID))"))
        XCTAssertTrue(helperMain.contains("TISSupport.bestSelectionTarget(TISSupport.inputSources(id: modeID))"))
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
        XCTAssertTrue(scripts.contains("KNOWTYPE_ACTIVE_INPUT_MODE_ID=\"com.knowtype.inputmethod.KnowType.Hans\""))
        XCTAssertTrue(scripts.contains("KNOWTYPE_LEGACY_INPUT_MODE_IDS=(\"com.knowtype.inputmethod.KnowType.Mode\")"))
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
            of: #"if\s+includeSelected\s*\{[\s\S]*?TISSupport\.postNotification\(kTISNotifySelectedKeyboardInputSourceChanged\)"#,
            options: .regularExpression
        ))
        XCTAssertTrue(helperSource.contains("bootstrap.singleSource"))
        XCTAssertTrue(helperSource.contains("if !parentEnabled || !modeEnabled"))
        XCTAssertTrue(helperSource.contains("preference.selected.parent.knowtype"))
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
        XCTAssertTrue(helperSource.contains("TISSupport.visibleUserModeCount"))
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
        XCTAssertTrue(helperSource.contains("requireSelected: requireSelected"))
        XCTAssertTrue(helperSource.contains("return OSStatus(paramErr)"))
        XCTAssertFalse(helperSource.contains("preferencesContainInputModeOrParent"))
        XCTAssertFalse(helperSource.contains("removeParent: !addLegacyParentAnchor"))
        XCTAssertFalse(helperSource.contains("addParent: addActive && addLegacyParentAnchor"))
        XCTAssertTrue(helperSource.contains("TISRegisterInputSource"))
    }

    func testInputMethodAppNormalLaunchIsServeOnly() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appMain = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeInputMethodApp/main.swift"),
            encoding: .utf8
        )
        let delegateStart = try XCTUnwrap(appMain.range(of: "final class KnowTypeAppDelegate"))
        let startupStart = try XCTUnwrap(
            appMain.range(
                of: "\nlet arguments = CommandLine.arguments",
                range: delegateStart.upperBound..<appMain.endIndex
            )
        )
        let delegateSource = String(appMain[delegateStart.lowerBound..<startupStart.lowerBound])

        XCTAssertTrue(delegateSource.contains("server = IMKServer"))
        XCTAssertTrue(delegateSource.contains("inputMethodLogger.notice"))
        for forbiddenCall in [
            "TextInputSourceActivation",
            "TISRegisterInputSource",
            "TISEnableInputSource",
            "TISSelectInputSource",
            "waitForInputSource",
            "waitForCurrentInputSourceID",
            "Thread.sleep"
        ] {
            XCTAssertFalse(
                delegateSource.contains(forbiddenCall),
                "Normal host startup must not call \(forbiddenCall)"
            )
        }
        XCTAssertFalse(appMain.contains("registerAndEnableInstalledBundle"))
        XCTAssertTrue(appMain.contains("KnowTypeInputMethodStartupPolicy.run("))
        XCTAssertTrue(appMain.contains("explicitCommandRequested: TextInputSourceActivation.handlesCommandLine(arguments)"))
        XCTAssertTrue(appMain.contains("application.run()"))
    }

    func testInputMethodAppKeepsExplicitInstalledActivationCommands() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let appMain = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeInputMethodApp/main.swift"),
            encoding: .utf8
        )
        let packageManifest = try String(
            contentsOf: rootURL.appendingPathComponent("Package.swift"),
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
        let smokeScript = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/smoke-inputmethod-install.sh"),
            encoding: .utf8
        )
        let installHelper = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/lib/inputmethod-installation.sh"),
            encoding: .utf8
        )
        let inputSourceTool = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeInputSourceTool/main.swift"),
            encoding: .utf8
        )
        let providerStorageCommand = try String(
            contentsOf: rootURL.appendingPathComponent(
                "Sources/KnowTypeProviders/ProviderProfileStorageCommand.swift"
            ),
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
        XCTAssertTrue(appMain.contains("--knowtype-migrate-provider-profiles"))
        XCTAssertTrue(appMain.contains("--knowtype-rollback-provider-profile-migration"))
        XCTAssertTrue(appMain.contains("ProviderProfileStorageCommand.migrate()"))
        XCTAssertTrue(appMain.contains("ProviderProfileStorageCommand.rollback("))
        XCTAssertTrue(appMain.contains("expectedCanonicalRevision: expectedRevision"))
        XCTAssertTrue(providerStorageCommand.contains("profileStore().migrateLegacyProfiles"))
        XCTAssertTrue(providerStorageCommand.contains("secretStore: KeychainSecretStore()"))
        XCTAssertTrue(providerStorageCommand.contains(#"environment["KNOWTYPE_APP_SUPPORT_DIR"]"#))
        XCTAssertTrue(providerStorageCommand.contains("provider.migration.credentials.rekeyed"))
        XCTAssertTrue(providerStorageCommand.contains("provider.migration.credentials.missing"))
        XCTAssertFalse(providerStorageCommand.contains(#"provider.migration.error=\(error.localizedDescription)"#))
        XCTAssertTrue(packageManifest.contains(#""KnowTypeInputSourceSupport", "KnowTypeProviders""#))
        XCTAssertTrue(appMain.contains("static func handlesCommandLine"))
        XCTAssertTrue(appMain.contains("let explicitSelect"))
        XCTAssertTrue(appMain.contains("|| explicitSelect"))
        XCTAssertTrue(appMain.contains("input-method-app"))
        XCTAssertTrue(appMain.contains("KnowTypeInputSourceIDs.activeMode"))
        XCTAssertTrue(appMain.contains("private typealias LSSupport = KnowTypeLaunchServicesSupport"))
        XCTAssertTrue(appMain.contains("private typealias TISSupport = KnowTypeTISSupport"))
        XCTAssertTrue(appMain.contains("TISSupport.deduplicatedActivationSources"))
        XCTAssertTrue(appMain.contains("TISSupport.bestSelectionTarget"))
        XCTAssertTrue(appMain.contains("TISSupport.bestSelectionTarget(TISSupport.inputSources(id: activeInputSourceID))"))
        XCTAssertTrue(appMain.contains("TISSupport.waitForCurrentInputSourceID(activeInputSourceID, timeout: 2.0)"))
        XCTAssertTrue(appMain.contains("TISSupport.waitForInputSource(id: parentInputSourceID, timeout: 5.0)"))
        XCTAssertTrue(appMain.contains("TISSupport.waitForInputSource(id: activeInputSourceID, timeout: 5.0)"))
        XCTAssertTrue(appMain.contains("TISSupport.inputSources(id: activeInputSourceID)"))
        XCTAssertTrue(appMain.contains("usesSingleInputSource"))
        XCTAssertTrue(appMain.contains("TISSupport.disableModesBeforeParent"))
        XCTAssertTrue(appMain.contains(".sorted(by: TISSupport.enableParentBeforeModes)"))
        XCTAssertTrue(appMain.contains("LSSupport.unregisterStaleLaunchServices"))
        XCTAssertFalse(appMain.contains("private static func inputSources("))
        XCTAssertFalse(appMain.contains("private static func runProcess"))
        XCTAssertTrue(appMain.contains("parentAnchorReady && modeReady"))
        XCTAssertTrue(appMain.contains("enable.parent.ready"))
        XCTAssertTrue(appMain.contains("enable.mode.ready"))
        XCTAssertTrue(appMain.contains("kTISPropertyInputSourceIsEnableCapable"))
        XCTAssertTrue(appMain.contains("kTISPropertyInputSourceIsSelectCapable"))
        XCTAssertTrue(appMain.contains("return status == noErr"))
        XCTAssertFalse(appMain.contains("return status == noErr && currentID == activeInputSourceID"))
        XCTAssertTrue(appMain.contains("enable.preference.writes=skipped"))
        XCTAssertTrue(appMain.contains("purge.legacy.preference.writes=skipped"))
        XCTAssertFalse(appMain.contains("CFPreferencesSetAppValue"))
        XCTAssertFalse(appMain.contains("AppleEnabledInputSources"))
        XCTAssertFalse(appMain.contains("AppleEnabledThirdPartyInputSources"))
        XCTAssertTrue(inputSourceTool.contains(#"case "disable":"#))
        XCTAssertTrue(inputSourceTool.contains(#"case "migrate-provider-profiles":"#))
        XCTAssertTrue(inputSourceTool.contains(#"case "downgrade-provider-profiles":"#))
        XCTAssertTrue(inputSourceTool.contains(#"case "rollback-provider-profile-migration":"#))
        XCTAssertTrue(inputSourceTool.contains("ProviderProfileStorageCommand.migrate()"))
        XCTAssertTrue(inputSourceTool.contains("sources.sorted(by: TISSupport.disableModesBeforeParent)"))
        XCTAssertTrue(inputSourceTool.contains(#"print("disabled.count=\(disabledCount)")"#))
        XCTAssertTrue(installScript.contains("quiesce_before_replace"))
        XCTAssertTrue(installScript.contains("QUIESCE_STARTED=1"))
        XCTAssertTrue(installScript.contains("restore_existing_input_source_after_failed_quiesce"))
        XCTAssertTrue(installScript.contains("Install failed after quiescing; restoring existing KnowType input-source enablement"))
        XCTAssertTrue(installScript.contains(#"knowtype_unregister_launchservices_records_except "$TARGET_PATH" 0"#))
        XCTAssertTrue(installScript.contains(#"knowtype_register_launchservices_path "$TARGET_PATH" 0"#))
        XCTAssertTrue(installScript.contains("bootstrap_input_source_best_effort || true"))
        XCTAssertTrue(installScript.contains("repair_preferences_best_effort || true"))
        XCTAssertTrue(installScript.contains("quiesce_before_replace\nfi\n\nprepare_source_artifacts"))
        XCTAssertTrue(installScript.contains("stop_input_method_host_after_quiesce\nrequire_input_method_host_stopped"))
        XCTAssertTrue(installScript.contains("stop_provider_profile_writer_hosts"))
        XCTAssertTrue(installScript.contains("knowtype_quit_system_settings_if_running 0"))
        XCTAssertTrue(installScript.contains("close KnowType Settings and System Settings before installing"))
        XCTAssertTrue(installScript.contains("migrate_provider_profiles"))
        XCTAssertTrue(installScript.contains("prepare_provider_storage_for_source_bundle"))
        XCTAssertTrue(installScript.contains("SOURCE_PROVIDER_STORAGE_GENERATION"))
        XCTAssertTrue(installScript.contains("skipped-pre-v2"))
        XCTAssertTrue(installScript.contains("rollback_provider_storage_after_failed_install"))
        XCTAssertTrue(installScript.contains(#""$provider_tool" migrate-provider-profiles"#))
        XCTAssertTrue(installScript.contains(#""$provider_tool" rollback-provider-profile-migration"#))
        XCTAssertTrue(installScript.contains(#""$provider_tool" downgrade-provider-profiles"#))
        XCTAssertFalse(installScript.contains("KnowTypeInputMethodApp\" --knowtype-migrate-provider-profiles"))
        XCTAssertTrue(installScript.contains("provider_storage_generation_for_bundle"))
        XCTAssertTrue(installHelper.contains("knowtype_legacy_provider_storage_is_compatible"))
        XCTAssertTrue(installHelper.contains("knowtype_provider_storage_is_pre_v2_compatible"))
        XCTAssertTrue(installHelper.contains("knowtype_migrate_provider_storage_for_bundle"))
        XCTAssertTrue(installScript.contains("knowtype_provider_storage_is_pre_v2_compatible"))
        XCTAssertTrue(installHelper.contains(#"payload["schemaVersion"] != 1"#))
        XCTAssertTrue(installHelper.contains(#"not isinstance(payload.get("profiles"), list)"#))
        let sourceGenerationGuard = try XCTUnwrap(
            installScript.range(of: #"installed_generation="$(provider_storage_generation_for_bundle "$TARGET_PATH" || true)""#)
        )
        let migrationInvocation = try XCTUnwrap(
            installScript.range(of: #"output="$("$provider_tool" migrate-provider-profiles 2>&1)""#)
        )
        XCTAssertLessThan(
            sourceGenerationGuard.lowerBound,
            migrationInvocation.lowerBound,
            "pre-v2 source bundles must be rejected before invoking an unsupported migration command"
        )
        XCTAssertTrue(installScript.contains("PROVIDER_MIGRATION_REVISION"))
        XCTAssertTrue(installScript.contains("keeping the new app instead of restoring an incompatible old binary"))
        XCTAssertFalse(installScript.contains("restore_provider_storage_snapshot"))
        XCTAssertTrue(installScript.contains("refusing to register the new input method"))
        let failedInstallProviderRollback = try XCTUnwrap(
            installScript.range(of: #"rollback_provider_storage_after_failed_install "$new_executable""#)
        )
        let failedInstallOldAppPublish = try XCTUnwrap(
            installScript.range(of: #"mv "$app_stage/KnowType.app" "$TARGET_PATH""#)
        )
        XCTAssertLessThan(
            failedInstallProviderRollback.lowerBound,
            failedInstallOldAppPublish.lowerBound,
            "provider metadata must be restored before a pre-v2 app becomes canonical"
        )
        XCTAssertTrue(
            installScript.contains(
                "migrate_provider_profiles\n\nlaunchservices_cleanup_output=\"$(knowtype_unregister_launchservices_records_except"
            )
        )
        XCTAssertTrue(installScript.contains("switch_away_before_replace"))
        XCTAssertTrue(installScript.contains("disable_input_sources_before_replace"))
        XCTAssertTrue(installScript.contains(#""$tool" disable --bundle-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID""#))
        XCTAssertTrue(installScript.contains("Disabled existing KnowType input-source rows before install"))
        XCTAssertTrue(installScript.contains("repair_preferences_best_effort"))
        XCTAssertTrue(installScript.contains("killall cfprefsd 2>/dev/null || true\nkillall TextInputMenuAgent 2>/dev/null || true\nkillall TextInputSwitcher 2>/dev/null || true\nsleep 0.5\nrepair_preferences_best_effort"))
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
        XCTAssertTrue(repairScript.contains("selected_current_id="))
        XCTAssertTrue(repairScript.contains(#"[[ "$selected_current_id" == "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" ]]"#))
        XCTAssertTrue(repairScript.contains("verified_selected == 1"))
        XCTAssertTrue(repairScript.contains("selected preferences were not rewritten"))
        XCTAssertTrue(repairScript.contains("input-source helper bootstrap failed"))
        XCTAssertTrue(repairScript.contains("bootstrap_args=("))
        XCTAssertTrue(repairScript.contains(#""$INPUTSOURCE_TOOL" "${bootstrap_args[@]}""#))
        XCTAssertTrue(installScript.contains("SCRIPT_DIR="))
        XCTAssertTrue(installScript.contains("SCRIPTS_DIR=\"$SCRIPT_DIR\""))
        XCTAssertTrue(installScript.contains(#"source "$SCRIPTS_DIR/lib/inputmethod-installation.sh""#))
        XCTAssertTrue(installScript.contains("knowtype_remove_local_inputmethod_bundle_if_safe"))
        XCTAssertTrue(installScript.contains("knowtype_cleanup_local_duplicate_bundles_except"))
        XCTAssertTrue(installScript.contains("knowtype_unregister_launchservices_records_except"))
        XCTAssertTrue(installScript.contains("STALE_LAUNCHSERVICES_CLEANUP_COUNT"))
        XCTAssertTrue(installScript.contains(#"knowtype_register_launchservices_path "$TARGET_PATH" 0"#))
        XCTAssertFalse(installScript.contains(#"knowtype_register_launchservices_path "$SOURCE_BUNDLE_PATH""#))
        XCTAssertFalse(installScript.contains(#"knowtype_register_launchservices_path "$FROM_BUNDLE""#))
        XCTAssertTrue(installScript.contains("--dry-run"))
        XCTAssertTrue(installScript.contains("Quiesce plan: switch away from KnowType, disable old KnowType input-source rows"))
        XCTAssertTrue(installScript.contains("Only the canonical installed app would be registered with LaunchServices"))
        XCTAssertTrue(installScript.contains("migrate provider profiles to providers.v2.json"))
        XCTAssertTrue(installScript.contains("the old migration CLI would not be invoked"))
        XCTAssertTrue(installScript.contains("require_input_method_host_stopped"))
        XCTAssertTrue(installScript.contains("process shutdown can flush Rime user data"))
        XCTAssertTrue(installScript.contains("--force-stop-host"))
        XCTAssertTrue(installScript.contains("FORCE_STOP_HOST"))
        XCTAssertTrue(installScript.contains("kill -TERM"))
        XCTAssertTrue(installScript.contains("kill -KILL"))
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
        XCTAssertTrue(installScript.contains("KnowType settings are available from the input-method menu: KnowType 设置..."))
        XCTAssertTrue(installScript.contains("KnowType Settings... in explicit English UI"))
        XCTAssertTrue(installScript.contains(#""$SCRIPTS_DIR/diagnose-inputmethod.sh" --json --path "$TARGET_PATH""#))
        XCTAssertFalse(installScript.contains(#""$SCRIPTS_DIR/diagnose-inputmethod.sh" --strict --path "$TARGET_PATH""#))
        XCTAssertTrue(installHelper.contains("knowtype_bundle_visible_input_mode_id"))
        XCTAssertTrue(installHelper.contains("knowtype_bundle_visible_input_mode_ids"))
        XCTAssertTrue(installHelper.contains("input-method bundle does not declare a menu-visible input mode"))
        XCTAssertTrue(installHelper.contains("menu-visible input modes (expected exactly one"))
        XCTAssertTrue(installHelper.contains(#"[[ "$visible_mode_id" != "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" ]]"#))
        XCTAssertTrue(installHelper.contains("input-method bundle declares unsupported menu-visible input mode"))
        XCTAssertTrue(installScript.contains(#"data.get("failures")"#))
        XCTAssertTrue(installScript.contains("Postflight uses the JSON install snapshot only"))
        XCTAssertTrue(installScript.contains("Stale compatibility PreferencePane that would be removed"))
        XCTAssertTrue(installScript.contains("REMOVED_STALE_PREFPANE=1"))
        XCTAssertTrue(installScript.contains("Removed stale KnowType compatibility PreferencePane"))
        XCTAssertTrue(installScript.contains("--add-active"))
        XCTAssertFalse(installScript.contains("--legacy-parent-anchor"))
        XCTAssertTrue(diagnosticScript.contains("ALLOW_LEGACY_PARENT_ANCHOR=0"))
        XCTAssertTrue(diagnosticScript.contains("--legacy-parent-anchor"))
        XCTAssertTrue(diagnosticScript.contains("visible .Hans input mode model"))
        XCTAssertTrue(diagnosticScript.contains("active KnowType input source"))
        XCTAssertTrue(diagnosticScript.contains("component-mode KnowType parent"))
        XCTAssertTrue(diagnosticScript.contains("dist/KnowType.app, release extraction, or backup paths can split helper selection from the real input menu"))
        XCTAssertFalse(installScript.contains(#""$INPUTSOURCE_TOOL" register --path "$TARGET_PATH""#))
        XCTAssertFalse(installScript.contains(#""$INPUTSOURCE_TOOL" select"#))
        XCTAssertFalse(installScript.contains(#""$executable" --knowtype-register-input-source --knowtype-enable-input-source"#))
        XCTAssertTrue(installScript.contains(#""$tool" bootstrap"#))
        XCTAssertTrue(rollbackScript.contains("purge_args=("))
        XCTAssertTrue(rollbackScript.contains("bootstrap_args=("))
        XCTAssertTrue(rollbackScript.contains(#""$inputsource_tool" "${purge_args[@]}""#))
        XCTAssertTrue(rollbackScript.contains(#""$inputsource_tool" "${bootstrap_args[@]}""#))
        XCTAssertTrue(rollbackScript.contains("knowtype_bundle_visible_input_mode_id"))
        XCTAssertTrue(rollbackScript.contains("restored_active_mode_id"))
        XCTAssertTrue(rollbackScript.contains("does not declare a menu-visible input mode"))
        XCTAssertTrue(rollbackScript.contains(#"--mode-id "$restored_active_mode_id""#))
        XCTAssertTrue(rollbackScript.contains("restored_legacy_args"))
        XCTAssertFalse(rollbackScript.contains(#"--knowtype-register-input-source --knowtype-enable-input-source"#))
        XCTAssertTrue(rollbackScript.contains("require_input_method_host_stopped"))
        XCTAssertTrue(rollbackScript.contains("prepare_provider_storage_for_restored_app"))
        XCTAssertTrue(rollbackScript.contains("migrate_provider_storage_for_restored_app"))
        XCTAssertTrue(rollbackScript.contains("restore_current_app_after_failed_provider_migration"))
        XCTAssertTrue(rollbackScript.contains(#""$provider_tool" downgrade-provider-profiles"#))
        XCTAssertTrue(rollbackScript.contains("knowtype_provider_storage_is_pre_v2_compatible"))
        XCTAssertTrue(rollbackScript.contains("knowtype_migrate_provider_storage_for_bundle"))
        XCTAssertTrue(rollbackScript.contains("KnowTypeProviderProfileStorageGeneration"))
        let explicitProviderDowngrade = try XCTUnwrap(
            rollbackScript.range(of: "\nprepare_provider_storage_for_restored_app\n")
        )
        let explicitOldAppPublish = try XCTUnwrap(
            rollbackScript.range(of: #"mv "$restore_app_staging_dir/KnowType.app" "$target_path""#)
        )
        XCTAssertLessThan(
            explicitProviderDowngrade.lowerBound,
            explicitOldAppPublish.lowerBound,
            "explicit rollback must prepare compatible provider metadata before publishing the backup app"
        )
        let restoredV2Migration = try XCTUnwrap(
            rollbackScript.range(of: "\nif ! migrate_provider_storage_for_restored_app; then")
        )
        let previousAppCleanup = try XCTUnwrap(
            rollbackScript.range(of: #"rm -rf "$current_app_staging_dir""#, range: restoredV2Migration.upperBound..<rollbackScript.endIndex)
        )
        XCTAssertLessThan(explicitOldAppPublish.lowerBound, restoredV2Migration.lowerBound)
        XCTAssertLessThan(
            restoredV2Migration.lowerBound,
            previousAppCleanup.lowerBound,
            "generation-2 rollback must migrate legacy provider metadata before discarding the previous app"
        )
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
        XCTAssertTrue(repairScript.contains(#""$INPUTSOURCE_TOOL" "${bootstrap_args[@]}""#))
        XCTAssertTrue(repairScript.contains(#""$INPUTSOURCE_TOOL" select"#))
        XCTAssertFalse(repairScript.contains(#""$BUNDLE_EXECUTABLE" --knowtype-register-input-source"#))
        XCTAssertFalse(repairScript.contains(#""$BUNDLE_EXECUTABLE" --knowtype-select-input-source"#))
        XCTAssertTrue(repairScript.contains("visible KnowType input mode"))
        XCTAssertTrue(repairScript.contains("continuing with enabled/history repair, menu refresh, and diagnostics"))
        XCTAssertTrue(repairScript.contains("selected preferences will not be rewritten"))
        XCTAssertTrue(repairScript.contains("selected preferences were not rewritten because helper selection was not verified"))
        XCTAssertTrue(smokeScript.contains(#"cd "$ROOT_DIR""#))
        XCTAssertTrue(smokeScript.contains(#"swift run --package-path "$ROOT_DIR" --quiet KnowTypeInputMethodApp --knowtype-rime-smoke"#))
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

    func testInstallerFailsClosedOnUnverifiedBackupsAndForeignPreferencePanes() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let helperSource = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/lib/inputmethod-installation.sh"),
            encoding: .utf8
        )
        let installScript = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/install-inputmethod.sh"),
            encoding: .utf8
        )
        let uninstallScript = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/uninstall-inputmethod.sh"),
            encoding: .utf8
        )
        let rollbackScript = try String(
            contentsOf: rootURL.appendingPathComponent("scripts/rollback-inputmethod.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(helperSource.contains("KNOWTYPE_BACKUP_MANIFEST_SCHEMA_VERSION=2"))
        XCTAssertTrue(helperSource.contains(#""appChecksum""#))
        XCTAssertTrue(helperSource.contains(#""appSigningRequirement""#))
        XCTAssertTrue(helperSource.contains(#""appSigningIdentity""#))
        XCTAssertTrue(helperSource.contains(#""prefPaneChecksum""#))
        XCTAssertTrue(helperSource.contains(#""prefPaneSigningRequirement""#))
        XCTAssertTrue(helperSource.contains(#""prefPaneSigningIdentity""#))
        XCTAssertTrue(helperSource.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(helperSource.contains("knowtype_validate_install_backup_for_restore"))
        XCTAssertTrue(helperSource.contains("legacy backup manifest lacks required integrity metadata"))
        XCTAssertTrue(helperSource.contains("schemaVersion 1 legacy backups"))
        XCTAssertTrue(helperSource.contains("KNOWTYPE_PREFPANE_BUNDLE_ID=\"com.knowtype.preferencepane\""))
        XCTAssertTrue(helperSource.contains("knowtype_is_canonical_local_preferencepane_path"))
        XCTAssertTrue(helperSource.contains("knowtype_is_safe_local_preferencepane_bundle_path"))
        XCTAssertTrue(helperSource.contains("knowtype_remove_local_preferencepane_bundle_if_safe"))
        XCTAssertTrue(helperSource.contains("knowtype_replace_local_preferencepane_bundle_atomically"))
        XCTAssertTrue(helperSource.contains("staged KnowType.prefPane failed validation"))
        XCTAssertTrue(helperSource.contains("foreign or unsafe same-name PreferencePane"))

        XCTAssertTrue(rollbackScript.contains("--allow-unverified-backup"))
        XCTAssertTrue(rollbackScript.contains(#"knowtype_validate_install_backup_for_restore "$backup_dir" "$ALLOW_UNVERIFIED_BACKUP""#))
        XCTAssertTrue(rollbackScript.contains(#"knowtype_require_safe_local_preferencepane_if_present "$prefpane_path""#))
        XCTAssertTrue(rollbackScript.contains(#"knowtype_remove_local_preferencepane_bundle_if_safe "$prefpane_path" 0"#))
        XCTAssertFalse(rollbackScript.contains(#"rm -rf -- "$prefpane_path""#))

        XCTAssertTrue(installScript.contains(#"--version "$LOCAL_SHORT_VERSION" --build "$LOCAL_BUILD_VERSION""#))
        XCTAssertTrue(installScript.contains(#"if [[ "$SOURCE_MODE" == "build" ]]; then"#))
        XCTAssertTrue(installScript.contains("build-inputmethod-bundle.sh"))
        XCTAssertTrue(installScript.contains("build-preference-pane.sh"))
        XCTAssertTrue(installScript.contains("knowtype_replace_local_preferencepane_bundle_atomically"))
        XCTAssertTrue(installScript.contains(#"knowtype_validate_install_backup_for_restore "$BACKUP_DIR" 0"#))
        XCTAssertTrue(installScript.contains(#"knowtype_require_safe_local_preferencepane_if_present "$PREFPANE_TARGET_PATH""#))
        XCTAssertTrue(installScript.contains(#"knowtype_remove_local_preferencepane_bundle_if_safe "$PREFPANE_TARGET_PATH" 0"#))
        XCTAssertFalse(installScript.contains(#"rm -rf -- "$PREFPANE_TARGET_PATH""#))

        XCTAssertTrue(uninstallScript.contains(#"knowtype_require_safe_local_preferencepane_if_present "$PREFPANE_TARGET_PATH""#))
        XCTAssertTrue(uninstallScript.contains(#"knowtype_remove_local_preferencepane_bundle_if_safe "$PREFPANE_TARGET_PATH" "$DRY_RUN""#))
        XCTAssertFalse(uninstallScript.contains(#"rm -rf -- "$PREFPANE_TARGET_PATH""#))
    }

    func testInputMethodInfoDeclaresVisibleHansInputMode() throws {
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
        XCTAssertEqual(plist["KnowTypeProviderProfileStorageGeneration"] as? Int, 2)
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "KnowTypeInputMethodIcon.icns")
        XCTAssertEqual(plist["tsInputMethodCharacterRepertoireKey"] as? [String], ["Hans", "Hant", "Hani", "Hanb", "Han"])

        let componentInputModeDict = try XCTUnwrap(plist["ComponentInputModeDict"] as? [String: Any])
        let modeList = try XCTUnwrap(componentInputModeDict["tsInputModeListKey"] as? [String: Any])
        XCTAssertEqual(Set(modeList.keys), Set([KnowTypeInputSourceIDs.activeMode]))
        let visibleMode = try XCTUnwrap(modeList[KnowTypeInputSourceIDs.activeMode] as? [String: Any])
        XCTAssertEqual(visibleMode["TISInputSourceID"] as? String, KnowTypeInputSourceIDs.activeMode)
        XCTAssertEqual(visibleMode["TISIntendedLanguage"] as? String, "zh-Hans")
        XCTAssertEqual(visibleMode["tsInputModeIsVisibleKey"] as? Bool, true)
        XCTAssertEqual(visibleMode["tsInputModeDefaultStateKey"] as? Bool, true)
        XCTAssertEqual(visibleMode["tsInputModePrimaryInScriptKey"] as? Bool, true)
        XCTAssertEqual(visibleMode["tsInputModeCharacterRepertoireKey"] as? [String], ["Hans", "Hant", "Hani", "Hanb", "Han"])
        XCTAssertEqual(componentInputModeDict["tsVisibleInputModeOrderedArrayKey"] as? [String], [KnowTypeInputSourceIDs.activeMode])
        XCTAssertEqual((plist["TISIconLabels"] as? [String: String])?["Primary"], "知")
        XCTAssertEqual(KnowTypeInputSourceIDs.activeMode, "com.knowtype.inputmethod.KnowType.Hans")
        XCTAssertEqual(KnowTypeInputSourceIDs.connectionName, "com.knowtype.inputmethod.KnowType_Connection")
        XCTAssertFalse(KnowTypeInputSourceIDs.legacyModes.contains("com.knowtype.inputmethod.KnowType.Hans"))
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

        XCTAssertTrue(englishStrings.contains(#""com.knowtype.inputmethod.KnowType" = "KnowType Input Method";"#))
        XCTAssertTrue(englishStrings.contains(#""com.knowtype.inputmethod.KnowType.Hans" = "KnowType";"#))
        XCTAssertFalse(englishStrings.contains("com.knowtype.inputmethod.KnowType.Mode"))
        XCTAssertTrue(chineseStrings.contains(#""com.knowtype.inputmethod.KnowType" = "知键输入法容器";"#))
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
        let componentInputModeDict = try XCTUnwrap(plist["ComponentInputModeDict"] as? [String: Any])
        let modeList = try XCTUnwrap(componentInputModeDict["tsInputModeListKey"] as? [String: Any])
        XCTAssertEqual(modeList.keys.sorted(), [KnowTypeInputSourceIDs.activeMode])
        XCTAssertEqual(componentInputModeDict["tsVisibleInputModeOrderedArrayKey"] as? [String], [KnowTypeInputSourceIDs.activeMode])
        XCTAssertNotEqual(KnowTypeInputSourceIDs.activeMode, KnowTypeInputSourceIDs.parent)
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

    func testProviderEndpointFixturesAndDiagnosticOutputsAreRedacted() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = rootURL.appendingPathComponent("Tests/Fixtures/provider-endpoint-summary.json")
        let helperURL = rootURL.appendingPathComponent("scripts/lib/provider_endpoint_summary.py")
        let fixtureProcess = Process()
        fixtureProcess.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        fixtureProcess.arguments = [helperURL.path, "--verify-fixtures", fixtureURL.path]
        try fixtureProcess.run()
        fixtureProcess.waitUntilExit()
        XCTAssertEqual(fixtureProcess.terminationStatus, 0)

        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-diagnose-provider-redaction-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }
        let home = testRoot.appendingPathComponent("Home", isDirectory: true)
        let bundle = testRoot.appendingPathComponent("KnowType.app", isDirectory: true)
        let support = home.appendingPathComponent("Library/Application Support/KnowType", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try makeMinimalBundle(at: bundle)
        try Data(
            """
            {"schemaVersion":2,"revision":1,"profiles":[{"id":"work","displayName":"Work","kind":"openAIResponses","baseURL":"https://user:pass@example.com/v1?api_key=TOPSECRET#trace","model":"gpt-test","timeoutSeconds":20,"headers":{},"isDefault":true}]}
            """.utf8
        ).write(to: support.appendingPathComponent("providers.v2.json"))
        let scriptURL = rootURL.appendingPathComponent("scripts/diagnose-inputmethod.sh")

        let jsonOutput = try runDiagnoseJSON(scriptURL: scriptURL, homeURL: home, bundleURL: bundle)
        let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: jsonOutput) as? [String: Any])
        let ai = try XCTUnwrap(snapshot["ai"] as? [String: Any])
        XCTAssertEqual(ai["storageState"] as? String, "canonical")
        let defaultProfile = try XCTUnwrap(ai["defaultProfile"] as? [String: Any])
        XCTAssertEqual(
            defaultProfile["baseURL"] as? String,
            "https://example.com/v1 [query redacted]"
        )
        let jsonText = try XCTUnwrap(String(data: jsonOutput, encoding: .utf8))
        XCTAssertFalse(jsonText.contains("TOPSECRET"))
        XCTAssertFalse(jsonText.contains("user:pass"))

        let textOutput = try runDiagnoseText(scriptURL: scriptURL, homeURL: home, bundleURL: bundle)
        XCTAssertTrue(textOutput.contains(
            "default AI provider: Work · openAIResponses · gpt-test · https://example.com/v1 [query redacted]"
        ))
        XCTAssertFalse(textOutput.contains("TOPSECRET"))
        XCTAssertFalse(textOutput.contains("user:pass"))
        XCTAssertFalse(textOutput.contains("api_key"))
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
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-diagnose-stdout-\(UUID().uuidString).json")
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-diagnose-stderr-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, "--json", "--path", bundleURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = homeURL.path
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["KNOWTYPE_INPUTSOURCE_TOOL"] = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("knowtype-inputsource-tool")
            .path
        process.environment = environment
        let output = try FileHandle(forWritingTo: outputURL)
        let error = try FileHandle(forWritingTo: errorURL)
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        try? output.close()
        try? error.close()
        let data = try Data(contentsOf: outputURL)
        if process.terminationStatus != 0 {
            let stderr = String(data: try Data(contentsOf: errorURL), encoding: .utf8) ?? ""
            XCTFail("diagnose-inputmethod.sh --json failed: \(stderr)")
        }
        return data
    }

    private func runDiagnoseText(
        scriptURL: URL,
        homeURL: URL,
        bundleURL: URL
    ) throws -> String {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-diagnose-stdout-\(UUID().uuidString).txt")
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-diagnose-stderr-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, "--path", bundleURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = homeURL.path
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["KNOWTYPE_INPUTSOURCE_TOOL"] = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("knowtype-inputsource-tool")
            .path
        process.environment = environment
        let output = try FileHandle(forWritingTo: outputURL)
        let error = try FileHandle(forWritingTo: errorURL)
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        try? output.close()
        try? error.close()
        let data = try Data(contentsOf: outputURL)
        if process.terminationStatus != 0 {
            let stderr = String(data: try Data(contentsOf: errorURL), encoding: .utf8) ?? ""
            XCTFail("diagnose-inputmethod.sh text mode failed: \(stderr)")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
