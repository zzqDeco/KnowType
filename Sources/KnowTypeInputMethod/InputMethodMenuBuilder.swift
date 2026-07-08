import Foundation
import KnowTypeCore
import KnowTypeSettingsUI

#if canImport(AppKit) && canImport(InputMethodKit)
import AppKit
@preconcurrency import InputMethodKit

enum KnowTypeInputMethodMenuItemKind: Equatable {
    case aiContinuation
    case modeStatus
    case separator
    case openLogs
    case openSupportFolder
    case openRimeUserFolder
    case settings
    case about
}

struct KnowTypeInputMethodMenuItemDescriptor: Equatable {
    var kind: KnowTypeInputMethodMenuItemKind
    var title: String
    var actionSelectorName: String?
    var keyEquivalent: String
    var stateRawValue: Int

    var isSeparator: Bool {
        kind == .separator
    }
}

enum KnowTypeInputMethodMenuBuilder {
    static func descriptors(
        runtimePreferences: InputMethodRuntimePreferences,
        inputModeState: InputModeState = InputModePreferences.standard.defaultState
    ) -> [KnowTypeInputMethodMenuItemDescriptor] {
        [
            .init(
                kind: .aiContinuation,
                title: SettingsLocalization.string("inputmethod.menu.aiContinuation"),
                actionSelectorName: "toggleAIContinuation:",
                keyEquivalent: "",
                stateRawValue: runtimePreferences.cloudContinuationEnabled
                    ? NSControl.StateValue.on.rawValue
                    : NSControl.StateValue.off.rawValue
            ),
            .init(
                kind: .modeStatus,
                title: modeStatusTitle(for: inputModeState),
                actionSelectorName: nil,
                keyEquivalent: "",
                stateRawValue: NSControl.StateValue.off.rawValue
            ),
            separator(),
            .init(
                kind: .openLogs,
                title: SettingsLocalization.string("inputmethod.menu.openLogs"),
                actionSelectorName: "openKnowTypeLogs:",
                keyEquivalent: "",
                stateRawValue: NSControl.StateValue.off.rawValue
            ),
            .init(
                kind: .openSupportFolder,
                title: SettingsLocalization.string("inputmethod.menu.openSupportFolder"),
                actionSelectorName: "openKnowTypeSupportFolder:",
                keyEquivalent: "",
                stateRawValue: NSControl.StateValue.off.rawValue
            ),
            .init(
                kind: .openRimeUserFolder,
                title: SettingsLocalization.string("inputmethod.menu.openRimeUserFolder"),
                actionSelectorName: "openRimeUserFolder:",
                keyEquivalent: "",
                stateRawValue: NSControl.StateValue.off.rawValue
            ),
            separator(),
            .init(
                kind: .settings,
                title: SettingsLocalization.string("inputmethod.menu.settings"),
                actionSelectorName: "showPreferences:",
                keyEquivalent: "",
                stateRawValue: NSControl.StateValue.off.rawValue
            ),
            .init(
                kind: .about,
                title: SettingsLocalization.string("inputmethod.menu.about"),
                actionSelectorName: "showAbout:",
                keyEquivalent: "",
                stateRawValue: NSControl.StateValue.off.rawValue
            )
        ]
    }

    static func makeMenu(
        target: AnyObject,
        runtimePreferences: InputMethodRuntimePreferences,
        inputModeState: InputModeState = InputModePreferences.standard.defaultState
    ) -> NSMenu {
        let menu = NSMenu(title: "KnowType")
        for descriptor in descriptors(runtimePreferences: runtimePreferences, inputModeState: inputModeState) {
            if descriptor.isSeparator {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(
                title: descriptor.title,
                action: descriptor.actionSelectorName.map(NSSelectorFromString),
                keyEquivalent: descriptor.keyEquivalent
            )
            item.target = target
            item.state = NSControl.StateValue(rawValue: descriptor.stateRawValue)
            item.isEnabled = descriptor.actionSelectorName != nil
            menu.addItem(item)
        }
        return menu
    }

    @discardableResult
    static func toggleAIContinuation(
        in store: any InputMethodRuntimePreferenceStore
    ) throws -> InputMethodRuntimePreferences {
        var preferences = store.loadPreferences()
        preferences.cloudContinuationEnabled.toggle()
        try store.savePreferences(preferences)
        return preferences
    }

    private static func separator() -> KnowTypeInputMethodMenuItemDescriptor {
        .init(
            kind: .separator,
            title: "",
            actionSelectorName: nil,
            keyEquivalent: "",
            stateRawValue: NSControl.StateValue.off.rawValue
        )
    }

    private static func modeStatusTitle(for state: InputModeState) -> String {
        let textMode = state.textMode == .chinese ? "中文输入" : "ASCII 输入"
        let punctuationMode = state.punctuationMode == .chinese ? "中文标点" : "英文标点"
        let width = state.symbolWidth == .halfWidth ? "半角" : "全角"
        return "\(textMode) · \(punctuationMode) · \(width)"
    }
}
#endif
