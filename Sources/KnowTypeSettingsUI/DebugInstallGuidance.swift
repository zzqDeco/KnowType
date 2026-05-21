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
            detail: "Copy KnowType.app into ~/Library/Input Methods. The install script purges stale .Mode development state, then launches the installed app so registration, enabling, and selection run from the app context. Open KnowType Settings from the input-method menu."
        ),
        DebugInstallStep(
            title: "Diagnose installation",
            detail: "Run the read-only diagnostic to verify bundle metadata, signing, packaged resources, Text Input Source registration, local data paths, and optional Gatekeeper or sandbox log hints."
        ),
        DebugInstallStep(
            title: "Request selection",
            detail: "Activate the text app you want to test, then use the selection script as a preflight. It requests selection through the installed KnowType app; final acceptance still requires typing a real probe in that app."
        ),
        DebugInstallStep(
            title: "Enable input source",
            detail: "If macOS asks to allow 知键/KnowType as an input method, click Allow. Then open System Settings > Keyboard > Text Input > Input Sources and enable or select KnowType if it does not switch automatically."
        ),
        DebugInstallStep(
            title: "Refresh registrar",
            detail: "If macOS keeps an old registration, run the repair script. It uses the installed input method app to remove stale LaunchServices records, disable legacy .Mode registrations, restore the third-party parent anchor plus .Hans mode, and retest selection."
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
        "./scripts/install-inputmethod.sh --with-prefpane",
        "./scripts/diagnose-inputmethod.sh --strict",
        "./scripts/diagnose-inputmethod.sh --strict --logs",
        "./scripts/repair-inputmethod-selection.sh",
        "./scripts/select-inputmethod.sh",
        "./scripts/select-inputmethod.sh --require-selected",
        "log stream --predicate 'process == \"KnowTypeInputMethodApp\"'"
    ]
}
