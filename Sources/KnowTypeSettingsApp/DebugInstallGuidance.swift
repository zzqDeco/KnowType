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
            detail: "Run the input method bundle build script. It auto-selects an Apple Development signing identity when one is available, and falls back to ad-hoc signing only when none is found."
        ),
        DebugInstallStep(
            title: "Install bundle",
            detail: "Copy KnowType.app into ~/Library/Input Methods. The install script launches the installed app with an activation flag so registration, enabling, and selection happen from the app context."
        ),
        DebugInstallStep(
            title: "Diagnose installation",
            detail: "Run the read-only diagnostic to verify bundle metadata, signing, packaged resources, Text Input Source registration, local data paths, and optional Gatekeeper or sandbox log hints."
        ),
        DebugInstallStep(
            title: "Request selection",
            detail: "Activate the text app you want to test, then use the selection helper only as a preflight. Final acceptance still requires typing a real probe in that app."
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
            detail: "Use the diagnostic log mode, Console.app, or the log command to inspect KnowTypeInputMethodApp, Gatekeeper, and input-source sandbox messages during local smoke tests."
        )
    ]

    static let commands: [String] = [
        "./scripts/build-inputmethod-bundle.sh",
        "CODESIGN_IDENTITY=\"Apple Development: Name (TEAMID)\" ./scripts/install-inputmethod.sh",
        "./scripts/install-inputmethod.sh",
        "./scripts/diagnose-inputmethod.sh --strict",
        "./scripts/diagnose-inputmethod.sh --strict --logs",
        "./scripts/select-inputmethod.sh",
        "./scripts/select-inputmethod.sh --require-selected",
        "log stream --predicate 'process == \"KnowTypeInputMethodApp\"'"
    ]
}
