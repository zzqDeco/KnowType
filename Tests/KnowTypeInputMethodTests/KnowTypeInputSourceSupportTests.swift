import Foundation
import KnowTypeInputSourceSupport
import XCTest

final class KnowTypeInputSourceSupportTests: XCTestCase {
    func testStripLSRegisterSuffixRemovesDumpAddress() {
        XCTAssertEqual(
            KnowTypeLaunchServicesSupport.stripLSRegisterSuffix(
                "/Users/me/Library/Input Methods/KnowType.app (0x1234ABCD)"
            ),
            "/Users/me/Library/Input Methods/KnowType.app"
        )
        XCTAssertEqual(
            KnowTypeLaunchServicesSupport.stripLSRegisterSuffix("/Applications/KnowType.app"),
            "/Applications/KnowType.app"
        )
    }

    func testExpandedPathExpandsHomeOnlyAtPathStart() {
        XCTAssertEqual(KnowTypeLaunchServicesSupport.expandedPath("~", homeDirectory: "/tmp/home"), "/tmp/home")
        XCTAssertEqual(
            KnowTypeLaunchServicesSupport.expandedPath("~/Library/Input Methods", homeDirectory: "/tmp/home"),
            "/tmp/home/Library/Input Methods"
        )
        XCTAssertEqual(KnowTypeLaunchServicesSupport.expandedPath("/tmp/~literal", homeDirectory: "/tmp/home"), "/tmp/~literal")
    }

    func testParseLaunchServicesPathsExtractsDedupedSortedBundlePaths() {
        let dump = """
        bundle id:
            path: /tmp/Z.app
            identifier: com.knowtype.inputmethod.KnowType (0x123)
        bundle id:
            path: /tmp/A.app
            identifier: com.other.App
        bundle id:
            path: /tmp/A.app
            identifier: com.knowtype.inputmethod.KnowType
        bundle id:
            path: /tmp/Z.app
            identifier: com.knowtype.inputmethod.KnowType
        """

        XCTAssertEqual(
            KnowTypeLaunchServicesSupport.parseLaunchServicesPaths(
                bundleID: "com.knowtype.inputmethod.KnowType",
                dump: dump
            ),
            ["/tmp/A.app", "/tmp/Z.app"]
        )
    }

    func testCanonicalBundlePathResolvesExistingSymlinkAndKeepsMissingPath() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("knowtype-inputsource-support-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: root)
        }
        let target = root.appendingPathComponent("Target.app", isDirectory: true)
        let link = root.appendingPathComponent("Link.app")
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertEqual(
            KnowTypeLaunchServicesSupport.canonicalBundlePath(link.path, fileManager: fileManager),
            target.path
        )
        XCTAssertEqual(
            KnowTypeLaunchServicesSupport.canonicalBundlePath(
                "~/Missing.app (0xFF)",
                fileManager: fileManager,
                homeDirectory: root.path
            ),
            root.appendingPathComponent("Missing.app").path
        )
    }

    func testUnregisterStaleLaunchServicesSkipsInstalledPathAndGarbageCollectsMissingFailures() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("knowtype-lsregister-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: root)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let current = root.appendingPathComponent("Current.app", isDirectory: true)
        let old = root.appendingPathComponent("Old.app", isDirectory: true)
        let missing = root.appendingPathComponent("Missing.app", isDirectory: true)
        try fileManager.createDirectory(at: current, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: old, withIntermediateDirectories: true)
        let lsregister = root.appendingPathComponent("lsregister")
        _ = fileManager.createFile(atPath: lsregister.path, contents: Data())
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lsregister.path)

        let dump = """
        bundle id:
            path: \(current.path)
            identifier: com.knowtype.inputmethod.KnowType
        bundle id:
            path: \(old.path)
            identifier: com.knowtype.inputmethod.KnowType
        bundle id:
            path: \(missing.path)
            identifier: com.knowtype.inputmethod.KnowType
        """
        var calls: [[String]] = []
        let unregistered = KnowTypeLaunchServicesSupport.unregisterStaleLaunchServices(
            path: current.path,
            bundleID: "com.knowtype.inputmethod.KnowType",
            lsregisterPath: lsregister.path,
            fileManager: fileManager,
            runner: { _, arguments in
                calls.append(arguments)
                if arguments == ["-dump"] {
                    return KnowTypeProcessResult(status: 0, output: dump)
                }
                if arguments == ["-u", old.path] || arguments == ["-gc"] {
                    return KnowTypeProcessResult(status: 0, output: "")
                }
                return KnowTypeProcessResult(status: 1, output: "")
            }
        )

        XCTAssertEqual(unregistered, 1)
        XCTAssertTrue(calls.contains(["-u", old.path]))
        XCTAssertTrue(calls.contains(["-u", missing.path]))
        XCTAssertTrue(calls.contains(["-gc"]))
        XCTAssertFalse(calls.contains(["-u", current.path]))
    }

    func testInputSourcePropertiesSignaturesAndOrderingRules() {
        let parent = KnowTypeInputSourceProperties(
            id: "com.knowtype.inputmethod.KnowType",
            type: "InputMode",
            isEnableCapable: true
        )
        let mode = KnowTypeInputSourceProperties(
            id: "com.knowtype.inputmethod.KnowType.Hans",
            modeID: "com.knowtype.inputmethod.KnowType.Hans",
            type: "InputMode",
            isEnabled: true,
            isSelectCapable: true
        )
        let betterActivation = KnowTypeInputSourceProperties(isEnableCapable: true, isSelectCapable: false)
        let worseActivation = KnowTypeInputSourceProperties(isEnableCapable: false, isSelectCapable: true)
        let betterSelection = KnowTypeInputSourceProperties(isEnabled: true, isSelectCapable: true)
        let worseSelection = KnowTypeInputSourceProperties(isEnabled: true, isSelectCapable: false)

        XCTAssertEqual(
            KnowTypeTISSupport.activationSignature(for: mode),
            "com.knowtype.inputmethod.KnowType.Hans|com.knowtype.inputmethod.KnowType.Hans|InputMode"
        )
        XCTAssertTrue(KnowTypeTISSupport.enableParentBeforeModes(parent, mode))
        XCTAssertTrue(KnowTypeTISSupport.disableModesBeforeParent(mode, parent))
        XCTAssertTrue(KnowTypeTISSupport.sourceIsBetterActivationTarget(betterActivation, than: worseActivation))
        XCTAssertTrue(KnowTypeTISSupport.sourceIsBetterSelectionTarget(betterSelection, than: worseSelection))
    }

    func testVisibleUserModeCountCountsEnabledSelectableUniqueIDs() {
        let sources = [
            KnowTypeInputSourceProperties(id: "a", isEnabled: true, isSelectCapable: true),
            KnowTypeInputSourceProperties(id: "a", isEnabled: true, isSelectCapable: true),
            KnowTypeInputSourceProperties(id: "b", isEnabled: true, isSelectCapable: false),
            KnowTypeInputSourceProperties(id: "c", isEnabled: false, isSelectCapable: true),
            KnowTypeInputSourceProperties(id: "d", isEnabled: true, isSelectCapable: true)
        ]

        XCTAssertEqual(KnowTypeTISSupport.visibleUserModeCount(sources), 2)
    }
}
