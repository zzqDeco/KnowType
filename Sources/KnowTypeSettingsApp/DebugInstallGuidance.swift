import Foundation

struct DebugInstallStep: Equatable, Identifiable {
    let title: String
    let detail: String

    var id: String { title }
}

enum DebugInstallGuidance {
    static let steps: [DebugInstallStep] = [
        DebugInstallStep(
            title: "Build and sign",
            detail: "Run the input method bundle build script. It uses ad-hoc signing by default, or Apple Development when CODESIGN_IDENTITY is set."
        ),
        DebugInstallStep(
            title: "Install bundle",
            detail: "Copy KnowType.app into ~/Library/Input Methods. The install script performs the copy, registration, and a best-effort selection request."
        ),
        DebugInstallStep(
            title: "Diagnose installation",
            detail: "Run the read-only diagnostic to verify bundle metadata, signing, packaged resources, Text Input Source registration, and local data paths."
        ),
        DebugInstallStep(
            title: "Request selection",
            detail: "Run the selection helper to ask macOS to switch to KnowType without reinstalling. Use the require-selected gate before manual typing acceptance."
        ),
        DebugInstallStep(
            title: "Enable input source",
            detail: "If macOS does not switch automatically, open System Settings > Keyboard > Text Input > Input Sources and enable or select KnowType."
        ),
        DebugInstallStep(
            title: "Refresh registrar",
            detail: "If macOS keeps an old registration, restart the input method process or log out and back in before retesting."
        ),
        DebugInstallStep(
            title: "Inspect logs",
            detail: "Use Console.app or the log command to inspect KnowTypeInputMethodApp messages during local smoke tests."
        )
    ]

    static let commands: [String] = [
        "./scripts/build-inputmethod-bundle.sh",
        "CODESIGN_IDENTITY=\"Apple Development: Name (TEAMID)\" ./scripts/install-inputmethod.sh",
        "./scripts/install-inputmethod.sh",
        "./scripts/diagnose-inputmethod.sh --strict",
        "./scripts/select-inputmethod.sh",
        "./scripts/select-inputmethod.sh --require-selected",
        "log stream --predicate 'process == \"KnowTypeInputMethodApp\"'"
    ]
}
