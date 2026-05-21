import Foundation

struct DebugInstallStep: Equatable, Identifiable {
    let title: String
    let detail: String

    var id: String { title }
}

enum DebugInstallGuidance {
    static var steps: [DebugInstallStep] {
        steps(preferredLanguages: Locale.preferredLanguages)
    }

    static func steps(preferredLanguages: [String]) -> [DebugInstallStep] {
        [
            DebugInstallStep(
                title: SettingsLocalization.string("settings.diagnostics.step.build.title", preferredLanguages: preferredLanguages),
                detail: SettingsLocalization.string("settings.diagnostics.step.build.detail", preferredLanguages: preferredLanguages)
            ),
            DebugInstallStep(
                title: SettingsLocalization.string("settings.diagnostics.step.install.title", preferredLanguages: preferredLanguages),
                detail: SettingsLocalization.string("settings.diagnostics.step.install.detail", preferredLanguages: preferredLanguages)
            ),
            DebugInstallStep(
                title: SettingsLocalization.string("settings.diagnostics.step.diagnose.title", preferredLanguages: preferredLanguages),
                detail: SettingsLocalization.string("settings.diagnostics.step.diagnose.detail", preferredLanguages: preferredLanguages)
            ),
            DebugInstallStep(
                title: SettingsLocalization.string("settings.diagnostics.step.select.title", preferredLanguages: preferredLanguages),
                detail: SettingsLocalization.string("settings.diagnostics.step.select.detail", preferredLanguages: preferredLanguages)
            ),
            DebugInstallStep(
                title: SettingsLocalization.string("settings.diagnostics.step.enable.title", preferredLanguages: preferredLanguages),
                detail: SettingsLocalization.string("settings.diagnostics.step.enable.detail", preferredLanguages: preferredLanguages)
            ),
            DebugInstallStep(
                title: SettingsLocalization.string("settings.diagnostics.step.refresh.title", preferredLanguages: preferredLanguages),
                detail: SettingsLocalization.string("settings.diagnostics.step.refresh.detail", preferredLanguages: preferredLanguages)
            ),
            DebugInstallStep(
                title: SettingsLocalization.string("settings.diagnostics.step.logs.title", preferredLanguages: preferredLanguages),
                detail: SettingsLocalization.string("settings.diagnostics.step.logs.detail", preferredLanguages: preferredLanguages)
            )
        ]
    }

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
