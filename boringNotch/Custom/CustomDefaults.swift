//
//  CustomDefaults.swift
//  boringNotch
//
//  Settings keys for the custom tabs: Things tasks, clipboard history, screenshots.
//

import Foundation
import Defaults

extension Defaults.Keys {
    // Things
    static let showTasksTab = Key<Bool>("custom.showTasksTab", default: true)
    static let thingsServerURL = Key<String>("custom.thingsServerURL", default: "") // e.g. https://<your-domain>/mcp — set in Settings, never commit it
    static let thingsAuthToken = Key<String>("custom.thingsAuthToken", default: "")
    static let thingsRefreshMinutes = Key<Int>("custom.thingsRefreshMinutes", default: 5)
    static let thingsLastListID = Key<String>("custom.thingsLastListID", default: "today")

    // Clipboard
    static let showClipboardTab = Key<Bool>("custom.showClipboardTab", default: true)
    static let clipboardHistoryLimit = Key<Int>("custom.clipboardHistoryLimit", default: 30)

    // Screenshots
    static let showScreenshotsTab = Key<Bool>("custom.showScreenshotsTab", default: true)
    static let screenshotsFolderBookmark = Key<Data?>("custom.screenshotsFolderBookmark", default: nil)
    static let screenshotsLimit = Key<Int>("custom.screenshotsLimit", default: 12)
}
