//
//  ClipboardView.swift
//  boringNotch
//
//  The Clipboard tab: click an entry to copy it back; hover for pin / delete.
//

import SwiftUI

struct ClipboardView: View {
    @ObservedObject private var manager = ClipboardManager.shared
    @State private var justCopied: UUID?

    private var sortedItems: [ClipboardItem] {
        manager.items.filter { manager.pinnedIDs.contains($0.id) } +
        manager.items.filter { !manager.pinnedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Буфер обмена")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(manager.items.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                Spacer()
                if !manager.items.isEmpty {
                    Button("Очистить") { withAnimation { manager.clearUnpinned() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                        .help("Удалить всё, кроме закреплённого")
                }
            }

            if manager.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 18))
                    Text("Скопируйте что-нибудь — оно появится здесь").font(.system(size: 11))
                }
                .foregroundStyle(.gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(sortedItems) { item in
                            ClipboardRow(
                                item: item,
                                pinned: manager.pinnedIDs.contains(item.id),
                                justCopied: justCopied == item.id,
                                onCopy: { copy(item) },
                                onPin: { withAnimation { manager.togglePin(item) } },
                                onDelete: { withAnimation { manager.remove(item) } }
                            )
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func copy(_ item: ClipboardItem) {
        manager.copy(item)
        justCopied = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if justCopied == item.id { justCopied = nil }
        }
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let pinned: Bool
    let justCopied: Bool
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            preview
            Spacer(minLength: 0)

            if justCopied {
                Text("Скопировано")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
            } else if hovering {
                Button(action: onPin) {
                    Image(systemName: pinned ? "pin.slash" : "pin")
                }
                .buttonStyle(.plain)
                .help(pinned ? "Открепить" : "Закрепить")
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Удалить")
            } else {
                if pinned {
                    Image(systemName: "pin.fill").font(.system(size: 9))
                }
                Text(item.date, style: .relative)
                    .font(.system(size: 10))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.gray)
        .font(.system(size: 11))
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.white.opacity(0.08) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onCopy)
        .help("Нажмите, чтобы скопировать")
    }

    @ViewBuilder
    private var preview: some View {
        HStack(spacing: 6) {
            if let icon = item.sourceApp?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            }
            switch item.content {
            case .text(let string):
                Text(string.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ⏎ "))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.white)
            case .image(let image, _):
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text("Изображение")
            case .files(let urls):
                Image(systemName: urls.count > 1 ? "doc.on.doc" : "doc")
                Text(urls.count > 1 ? "\(urls[0].lastPathComponent) и ещё \(urls.count - 1)" : urls[0].lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.white)
            }
        }
    }
}
