//
//  ScreenshotsView.swift
//  boringNotch
//
//  The Screenshots tab: newest screenshots as a horizontal strip.
//  Click = copy image, double-click = open, drag = drop into any app, right-click = more.
//

import SwiftUI

struct ScreenshotsView: View {
    @ObservedObject private var manager = ScreenshotsManager.shared
    @State private var copiedURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Скриншоты")
                    .font(.system(size: 13, weight: .semibold))
                if let folder = manager.folderURL {
                    Text(folder.lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                }
                Spacer()
                if let error = manager.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                Button {
                    manager.chooseFolder()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.gray)
                .help("Выбрать папку со скриншотами")
            }

            if manager.folderURL == nil {
                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 18))
                    Button("Выбрать папку со скриншотами") { manager.chooseFolder() }
                        .font(.system(size: 11))
                }
                .foregroundStyle(.gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if manager.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle").font(.system(size: 18))
                    Text("Скриншотов пока нет  (⇧⌘4)").font(.system(size: 11))
                }
                .foregroundStyle(.gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(manager.items) { item in
                            ScreenshotTile(item: item, copied: copiedURL == item.url)
                                .onTapGesture(count: 2) { manager.openFile(item) }
                                .onTapGesture { copy(item) }
                                .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                                .contextMenu {
                                    Button("Скопировать") { copy(item) }
                                    Button("Открыть") { manager.openFile(item) }
                                    Button("Показать в Finder") { manager.revealInFinder(item) }
                                    Divider()
                                    Button("Переместить в корзину", role: .destructive) { manager.moveToTrash(item) }
                                }
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
        .padding(.horizontal, 4)
        .onAppear { manager.reload() }
    }

    private func copy(_ item: ScreenshotItem) {
        manager.copyImage(item)
        copiedURL = item.url
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedURL == item.url { copiedURL = nil }
        }
    }
}

private struct ScreenshotTile: View {
    let item: ScreenshotItem
    let copied: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(3)
                } else {
                    Image(systemName: "photo").foregroundStyle(.gray)
                }
                if copied {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black.opacity(0.55))
                    Label("Скопировано", systemImage: "checkmark")
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .frame(width: 130, height: 82)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(hovering ? Color.white.opacity(0.35) : .clear, lineWidth: 1)
            )

            Text(item.date, style: .relative)
                .font(.system(size: 9))
                .foregroundStyle(.gray)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(item.url.lastPathComponent)
    }
}
