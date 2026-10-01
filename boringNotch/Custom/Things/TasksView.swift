//
//  TasksView.swift
//  boringNotch
//
//  The Tasks tab: list switcher on the left, tasks of the selected list on the right.
//  Click the circle to complete a task; click it again (before the next refresh) to undo.
//

import SwiftUI
import Defaults

struct TasksView: View {
    @ObservedObject private var manager = ThingsManager.shared
    @Default(.thingsServerURL) private var serverURL

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            sidebar
                .frame(width: 150)
            Divider().opacity(0.3)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 4)
        .onAppear { manager.activate() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(ThingsList.builtIns) { list in
                        listButton(list)
                    }
                }
            }

            HStack(spacing: 6) {
                containerMenu
                Spacer(minLength: 0)
                Button {
                    Task { await manager.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(manager.isLoading ? 360 : 0))
                        .animation(manager.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: manager.isLoading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.gray)
                .help("Обновить")
            }
            .padding(.top, 4)
        }
    }

    private func listButton(_ list: ThingsList) -> some View {
        let selected = manager.selectedList == list
        return Button {
            manager.select(list)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: list.icon)
                    .frame(width: 14)
                Text(list.title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? .white : .gray)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.white.opacity(0.12) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Areas and projects live in a menu — there can be dozens of them.
    private var containerMenu: some View {
        Menu {
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
            if manager.areas.isEmpty && manager.projects.isEmpty {
                Text("Нет областей и проектов")
            }
        } label: {
            Label("Списки", systemImage: "list.bullet")
                .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(.gray)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(manager.selectedList.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("\(manager.tasks.count - manager.recentlyCompleted.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                Spacer()
                if let error = manager.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .help(error)
                }
            }

            if serverURL.isEmpty {
                placeholder("Укажите адрес сервера Things в настройках → Tasks", icon: "gearshape")
            } else if manager.tasks.isEmpty {
                if manager.isLoading {
                    placeholder("Загрузка…", icon: "hourglass")
                } else if manager.errorMessage == nil {
                    placeholder("Задач нет", icon: "checkmark.circle")
                } else {
                    Spacer()
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(manager.tasks) { task in
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
            Text(text).font(.system(size: 11))
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
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(completed ? Color.accentColor : .gray)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 12))
                    .strikethrough(completed)
                    .foregroundStyle(completed ? .gray : .white)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if task.note?.isEmpty == false {
                Image(systemName: "doc.text")
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
                    .help(task.note ?? "")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.white.opacity(0.06) : .clear)
        )
        .onHover { hovering = $0 }
        .opacity(completed ? 0.6 : 1)
    }
}
