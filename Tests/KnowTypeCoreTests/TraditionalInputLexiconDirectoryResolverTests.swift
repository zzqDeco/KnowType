import Foundation
import XCTest
@testable import KnowTypeCore

final class TraditionalInputLexiconDirectoryResolverTests: XCTestCase {
    func testDefaultDirectoryUsesKnowTypeApplicationSupport() {
        let home = URL(fileURLWithPath: "/tmp/knowtype-home")

        XCTAssertEqual(
            TraditionalInputLexiconDirectoryResolver.defaultDirectories(
                environment: [:],
                homeDirectory: home
            ).map(\.path),
            ["/tmp/knowtype-home/Library/Application Support/KnowType/Lexicons"]
        )
    }

    func testEnvironmentDirectoriesAreResolvedBeforeApplicationSupportAndDeduplicated() {
        let home = URL(fileURLWithPath: "/tmp/knowtype-home")

        let directories = TraditionalInputLexiconDirectoryResolver.defaultDirectories(
            environment: [
                TraditionalInputLexiconDirectoryResolver.environmentDirectoryKey: "/tmp/one",
                TraditionalInputLexiconDirectoryResolver.environmentDirectoriesKey: "/tmp/two:/tmp/one:/tmp/three"
            ],
            homeDirectory: home
        )

        XCTAssertEqual(directories.map(\.path), [
            "/tmp/one",
            "/tmp/two",
            "/tmp/three",
            "/tmp/knowtype-home/Library/Application Support/KnowType/Lexicons"
        ])
    }

    func testEnvironmentDirectoriesTrimEmptyPaths() {
        let home = URL(fileURLWithPath: "/tmp/knowtype-home")

        let directories = TraditionalInputLexiconDirectoryResolver.defaultDirectories(
            environment: [
                TraditionalInputLexiconDirectoryResolver.environmentDirectoryKey: "  /tmp/one  ",
                TraditionalInputLexiconDirectoryResolver.environmentDirectoriesKey: " : /tmp/two : "
            ],
            homeDirectory: home
        )

        XCTAssertEqual(directories.map(\.path), [
            "/tmp/one",
            "/tmp/two",
            "/tmp/knowtype-home/Library/Application Support/KnowType/Lexicons"
        ])
    }

    func testUniqueDirectoriesUsesStandardizedFilePath() {
        let directories = TraditionalInputLexiconDirectoryResolver.uniqueDirectories([
            URL(fileURLWithPath: "/tmp/one"),
            URL(fileURLWithPath: "/tmp/../tmp/one"),
            URL(fileURLWithPath: "/tmp/two")
        ])

        XCTAssertEqual(directories.map(\.path), [
            "/tmp/one",
            "/tmp/two"
        ])
    }
}
