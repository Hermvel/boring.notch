//
//  ScreenshotsManager.swift
//  boringNotch
//
//  Shows the newest images from a folder the user picks once (the app is sandboxed,
//  so access is kept via a security-scoped bookmark). The folder is watched and the
//  list updates as soon as a new screenshot lands.
//

import AppKit
import Combine
import Defaults
import ImageIO
import UniformTypeIdentifiers

struct ScreenshotItem: Identifiable, Equatable {
    let url: URL
    let date: Date
    let thumbnail: NSImage?
    var id: URL { url }

    static func == (lhs: ScreenshotItem, rhs: ScreenshotItem) -> Bool {
        lhs.url == rhs.url && lhs.date == rhs.date
    }
}

@MainActor
final class ScreenshotsManager: ObservableObject {
    static let shared = ScreenshotsManager()

    @Published private(set) var items: [ScreenshotItem] = []
    @Published private(set) var folderURL: URL?
    @Published private(set) var errorMessage: String?

    private var watcher: DispatchSourceFileSystemObject?
    private var reloadWorkItem: DispatchWorkItem?
    private var thumbnailCache: [URL: (Date, NSImage)] = [:]

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif"]

    private init() {
        restoreFolder()
    }

    // MARK: - Folder access

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать"
        panel.message = "Выберите папку, куда macOS сохраняет скриншоты (обычно «Рабочий стол»)"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            Defaults[.screenshotsFolderBookmark] = bookmark
            openFolder(url)
        } catch {
            errorMessage = "Не удалось сохранить доступ к папке: \(error.localizedDescription)"
        }
    }

    private func restoreFolder() {
        guard let bookmark = Defaults[.screenshotsFolderBookmark] else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            errorMessage = "Нет доступа к папке — выберите её заново"
            return
        }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            Defaults[.screenshotsFolderBookmark] = fresh
        }
        openFolder(url)
    }

    private func openFolder(_ url: URL) {
        folderURL?.stopAccessingSecurityScopedResource()
        stopWatching()
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Нет доступа к папке — выберите её заново"
            return
        }
        folderURL = url
        errorMessage = nil
        thumbnailCache = [:]
        reload()
        startWatching(url)
    }

    // MARK: - Watching

    private func startWatching(_ url: URL) {
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    /// macOS writes a screenshot in several steps — wait a moment so the file is complete.
    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        reloadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    func reload() {
        guard let folderURL else { return }
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []

        let images: [(URL, Date)] = urls.compactMap { url in
            guard Self.imageExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { return nil }
            return (url, values.creationDate ?? .distantPast)
        }

        let newest = images
            .sorted { $0.1 > $1.1 }
            .prefix(max(1, Defaults[.screenshotsLimit]))

        items = newest.map { url, date in
            ScreenshotItem(url: url, date: date, thumbnail: thumbnail(for: url, date: date))
        }
        let visible = Set(items.map(\.url))
        thumbnailCache = thumbnailCache.filter { visible.contains($0.key) }
    }

    /// Downsampled thumbnail — full-size Retina screenshots would eat a lot of memory.
    private func thumbnail(for url: URL, date: Date) -> NSImage? {
        if let cached = thumbnailCache[url], cached.0 == date { return cached.1 }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 360,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        thumbnailCache[url] = (date, image)
        return image
    }

    // MARK: - Actions

    func copyImage(_ item: ScreenshotItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let image = NSImage(contentsOf: item.url) {
            pasteboard.writeObjects([image, item.url as NSURL])
        } else {
            pasteboard.writeObjects([item.url as NSURL])
        }
    }

    func openFile(_ item: ScreenshotItem) {
        NSWorkspace.shared.open(item.url)
    }

    func revealInFinder(_ item: ScreenshotItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func moveToTrash(_ item: ScreenshotItem) {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
