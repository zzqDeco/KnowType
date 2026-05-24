import Foundation
import KnowTypeCore

#if canImport(AppKit) && canImport(InputMethodKit)
import AppKit
@preconcurrency import InputMethodKit

enum KnowTypeInputMethodMenuItemKind: Equatable {
    case aiContinuation
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
        runtimePreferences: InputMethodRuntimePreferences
    ) -> [KnowTypeInputMethodMenuItemDescriptor] {
        [
            .init(
                kind: .aiContinuation,
                title: "AI Continuation",
                actionSelectorName: "toggleAIContinuation:",
                keyEquivalent: "",
                stateRawValue: runtimePreferences.cloudContinuationEnabled
                    ? NSControl.StateValue.on.rawValue
                    : NSControl.StateValue.off.rawValue
            ),
            separator(),
            .init(
                kind: .openLogs,
                title: "Open Logs...",
                actionSelectorName: "openKnowTypeLogs:",
                keyEquivalent: "",
                stateRawValue: NSControl.StateValue.off.rawValue
            ),
            .init(
                kind: .openSupportFolder,
                title: "Open Support Folder...",
                actionSelectorName: "openKnowTypeSupportFolder:",
                keyEquivalent: "",
                stateRawValue: NSControl.StateValue.off.rawValue
            ),
            .init(
                kind: .openRimeUserFolder,
                title: "Open Rime User Folder...",
                actionSelectorName: "openRimeUserFolder:",
                keyEquivalent: "",
                stateRawValue: NSControl.StateValue.off.rawValue
            ),
            separator(),
            .init(
                kind: .settings,
                title: "KnowType Settings...",
                actionSelectorName: "showPreferences:",
                keyEquivalent: "",
                stateRawValue: NSControl.StateValue.off.rawValue
            ),
            .init(
                kind: .about,
                title: "About KnowType...",
                actionSelectorName: "showAbout:",
                keyEquivalent: "",
                stateRawValue: NSControl.StateValue.off.rawValue
            )
        ]
    }

    static func makeMenu(
        target: AnyObject,
        runtimePreferences: InputMethodRuntimePreferences
    ) -> NSMenu {
        let menu = NSMenu(title: "KnowType")
        for descriptor in descriptors(runtimePreferences: runtimePreferences) {
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
}
#endif
