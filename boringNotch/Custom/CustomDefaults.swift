//
//  CustomDefaults.swift
//  boringNotch
//
//  Settings keys for the custom sections: Things tasks, calendar, clipboard, screenshots.
//
//  Key names must not contain dots: Defaults observes UserDefaults via KVO and a dot
//  is treated as a key path, which silently breaks live updates in Settings.
//

import Foundation
import Defaults

extension Defaults.Keys {
    // Things
    static let showTasksTab = Key<Bool>("custom_showTasksTab", default: true)
    static let thingsServerURL = Key<String>("custom_thingsServerURL", default: "") // e.g. https://<your-domain>/mcp — set in Settings, never commit it
    static let thingsAuthToken = Key<String>("custom_thingsAuthToken", default: "")
    static let thingsRefreshMinutes = Key<Int>("custom_thingsRefreshMinutes", default: 5)
    static let thingsLastListID = Key<String>("custom_thingsLastListID", default: "today")
    /// Areas/projects hidden from the list picker (ThingsList ids, e.g. "project:<uuid>").
    static let thingsHiddenListIDs = Key<[String]>("custom_thingsHiddenListIDs", default: [])

    // Calendar section
    static let showCalendarSection = Key<Bool>("custom_showCalendarSection", default: true)
    static let calendarUpcomingDays = Key<Int>("custom_calendarUpcomingDays", default: 14)

    // Clipboard
    static let showClipboardTab = Key<Bool>("custom_showClipboardTab", default: true)
    static let clipboardHistoryLimit = Key<Int>("custom_clipboardHistoryLimit", default: 30)

    // Screenshots
    static let showScreenshotsTab = Key<Bool>("custom_showScreenshotsTab", default: true)
    static let screenshotsFolderBookmark = Key<Data?>("custom_screenshotsFolderBookmark", default: nil)
    static let screenshotsLimit = Key<Int>("custom_screenshotsLimit", default: 12)
}

enum CustomDefaultsMigration {
    /// Copies values saved under the old dotted key names ("custom.xxx") to the new ones, once.
    static func run() {
        let store = UserDefaults.standard
        let names = [
            "showTasksTab", "thingsServerURL", "thingsAuthToken", "thingsRefreshMinutes", "thingsLastListID",
            "showClipboardTab", "clipboardHistoryLimit",
            "showScreenshotsTab", "screenshotsFolderBookmark", "screenshotsLimit",
        ]
        for name in names {
            let old = "custom.\(name)"
            guard let value = store.object(forKey: old) else { continue }
            if store.object(forKey: "custom_\(name)") == nil {
                store.set(value, forKey: "custom_\(name)")
            }
            store.removeObject(forKey: old)
        }
    }
}
