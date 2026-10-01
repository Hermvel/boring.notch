//
//  TasksView.swift
//  boringNotch
//
//  The Tasks tab.
//  Top line: list/project picker + tag filter chips + count/refresh.
//  Below: tasks in two columns. Click the circle to complete; click again (before refresh) to undo.
//

import SwiftUI
import Defaults

struct TasksView: View {
    @ObservedObject private var manager = ThingsManager.shared
    @Default(.thingsServerURL) private var serverURL

    private let columns = [
        GridItem(.flexible(), spacing: 6, alignment: .topLeading),
        GridItem(.flexible(), spacing: 6, alignment: .topLeading),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            topBar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { manager.activate() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            listPicker
            tagChips
            statusAccessories
        }
        .frame(height: 22)
    }

    /// Drop-down with the built-in lists, areas and projects.
    private var listPicker: some View {
        Menu {
            ForEach(ThingsList.builtIns) { list in
                Button {
                    manager.select(list)
                } label: {
                    Label(list.title, systemImage: list.icon)
                }
            }
            if !manager.areas.isEmpty {
                Section("Области") {
                    ForEach(manager.areas) { list in
                        Button(list.title) { manager.select(list) }
                    }
                }
            }
            if !manager.projects.isEmpty {
                Section("Проекты") {
                    ForEach(manager.projects) { list in
                        Button(list.title) { manager.select(list) }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: manager.selectedList.icon)
                    .font(.system(size: 11))
                Text(manager.selectedList.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.gray)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .frame(maxWidth: 170, alignment: .leading)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Tags present in the current list; several can be selected (task matches any of them).
    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if !manager.selectedTags.isEmpty {
                    chip(title: "Все", selected: false, systemImage: "xmark") {
                        withAnimation(.smooth(duration: 0.2)) { manager.selectedTags = [] }
                    }
                }
                ForEach(manager.availableTags) { tag in
                    chip(title: tag.name, selected: manager.selectedTags.contains(tag.id)) {
                        withAnimation(.smooth(duration: 0.2)) { manager.toggleTag(tag.id) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func chip(title: String, selected: Bool, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 8, weight: .bold))
                }
                Text(title).lineLimit(1)
            }
            .font(.system(size: 10, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? .black : .gray)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(selected ? Color.white.opacity(0.85) : Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    private var statusAccessories: some View {
        HStack(spacing: 6) {
            if let error = manager.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .help(error)
            }
            Text("\(manager.visibleTasks.count - manager.visibleTasks.filter { manager.recentlyCompleted.contains($0.uuid) }.count)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.gray)
            Button {
                Task { await manager.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .rotationEffect(.degrees(manager.isLoading ? 360 : 0))
                    .animation(manager.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: manager.isLoading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.gray)
            .help("Обновить")
        }
        .fixedSize()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if serverURL.isEmpty {
            placeholder("Укажите адрес сервера Things в настройках → Tasks", icon: "gearshape")
        } else if manager.tasks.isEmpty {
            if manager.isLoading {
                placeholder("Загрузка…", icon: "hourglass")
            } else if let error = manager.errorMessage {
                placeholder(error, icon: "exclamationmark.triangle")
            } else {
                placeholder("Задач нет", icon: "checkmark.circle")
            }
        } else if manager.visibleTasks.isEmpty {
            placeholder("Нет задач с выбранными тегами", icon: "tag")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                    ForEach(manager.visibleTasks) { task in
                        TaskRow(
                            task: task,
                            subtitle: subtitle(for: task),
                            completed: manager.recentlyCompleted.contains(task.uuid)
                        ) {
                            withAnimation(.smooth(duration: 0.2)) {
                                manager.toggleCompleted(task)
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private func subtitle(for task: ThingsTask) -> String? {
        var parts: [String] = []
        // Project name is redundant inside that project's own list.
        if case .project = manager.selectedList.kind {} else if let title = manager.projectTitle(for: task) {
            parts.append(title)
        }
        if let date = task.scheduledFor, manager.selectedList != .today {
            parts.append(Self.formatDate(date))
        }
        if let deadline = task.realDeadline {
            parts.append("⚑ " + Self.formatDate(deadline))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func placeholder(_ text: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 18))
            Text(text)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .foregroundStyle(.gray)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let inputFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let outputFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM"
        return f
    }()

    static func formatDate(_ raw: String) -> String {
        guard let date = inputFormatter.date(from: String(raw.prefix(10))) else { return raw }
        if Calendar.current.isDateInToday(date) { return "сегодня" }
        if Calendar.current.isDateInTomorrow(date) { return "завтра" }
        return outputFormatter.string(from: date)
    }
}

private struct TaskRow: View {
    let task: ThingsTask
    let subtitle: String?
    let completed: Bool
    let onToggle: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button(action: onToggle) {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(completed ? Color.accentColor : .gray)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 11.5))
                    .strikethrough(completed)
                    .foregroundStyle(completed ? .gray : .white)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if task.note?.isEmpty == false {
                Image(systemName: "doc.text")
                    .font(.system(size: 8))
                    .foregroundStyle(.gray)
                    .help(task.note ?? "")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(hovering ? 0.09 : 0.04))
        )
        .onHover { hovering = $0 }
        .opacity(completed ? 0.6 : 1)
    }
}
