import Foundation
import KnowTypeCore

enum InputClientWriteMode: String, Sendable, Equatable {
    case inlineComposition
    case commitOnlyComposition
    case asciiPassthrough
    case disabled
}

struct InputClientCompatibilityPolicy: Sendable {
    private let overrideStore: InputClientWriteModeOverrideStore?

    init(userDefaults: UserDefaults? = UserDefaults(suiteName: UserDefaultsInputModePreferenceStore.defaultSuiteName)) {
        self.overrideStore = userDefaults.map(InputClientWriteModeOverrideStore.init(userDefaults:))
    }

    func writeMode(
        bundleIdentifier: String?,
        inputModeState: InputModeState,
        hasActiveComposition: Bool,
        hasClient: Bool
    ) -> InputClientWriteMode {
        guard hasClient else {
            return .disabled
        }
        if let override = overrideWriteMode(bundleIdentifier: bundleIdentifier) {
            return override
        }
        if isCompatibilityBundle(bundleIdentifier) {
            return hasActiveComposition || inputModeState.textMode == .chinese
                ? .commitOnlyComposition
                : .asciiPassthrough
        }
        if inputModeState.textMode == .ascii,
           !hasActiveComposition {
            return .asciiPassthrough
        }
        return .inlineComposition
    }

    private func overrideWriteMode(bundleIdentifier: String?) -> InputClientWriteMode? {
        guard let bundleIdentifier,
              let rawValue = overrideStore?.writeModeOverride(for: bundleIdentifier) else {
            return nil
        }
        return InputClientWriteMode(rawValue: rawValue)
    }

    private func isCompatibilityBundle(_ bundleIdentifier: String?) -> Bool {
        InputModeAppPolicy.usesCodeAppState(appBundleID: bundleIdentifier)
    }
}

private final class InputClientWriteModeOverrideStore: @unchecked Sendable {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func writeModeOverride(for bundleIdentifier: String) -> String? {
        userDefaults.string(forKey: "input.client.\(bundleIdentifier).writeMode")
    }
}
