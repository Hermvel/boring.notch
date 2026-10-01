//
//  CustomSettingsViews.swift
//  boringNotch
//
//  Settings panes for the custom tabs, plugged into SettingsView's sidebar.
//

import SwiftUI
import Defaults

struct TasksSettings: View {
    @ObservedObject private var manager = ThingsManager.shared
    @Default(.thingsServerURL) private var serverURL
    @Default(.thingsAuthToken) private var token
    @Default(.thingsRefreshMinutes) private var refreshMinutes
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        Form {
            Defaults.Toggle(key: .showTasksTab) {
                Text("Show Tasks tab")
            }

            Section {
                TextField("Server URL", text: $serverURL, prompt: Text("https://…/mcp"))
                SecureField("Token (optional)", text: $token)
                Stepper(value: $refreshMinutes, in: 1...60) {
                    Text("Refresh every \(refreshMinutes) min")
                }
                HStack {
                    Button(testing ? "Checking…" : "Test connection") { test() }
                        .disabled(testing || serverURL.isEmpty)
                    if let testResult {
                        Text(testResult)
                            .font(.callout)
                            .foregroundStyle(testResult.hasPrefix("✓") ? .green : .red)
                            .lineLimit(2)
                    }
                }
            } header: {
                Text("Things Cloud MCP server")
            } footer: {
                Text("Address of your self-hosted things-cloud-mcp endpoint. The token is sent as \"Authorization: Bearer …\" if set.")
            }

            listVisibilitySection(title: "Areas in the list picker", lists: manager.allAreas)
            listVisibilitySection(title: "Projects in the list picker", lists: manager.allProjects)
        }
        .task {
            if manager.allAreas.isEmpty && manager.allProjects.isEmpty && !serverURL.isEmpty {
                await manager.loadContainers()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Tasks")
    }

    @ViewBuilder
    private func listVisibilitySection(title: LocalizedStringKey, lists: [ThingsList]) -> some View {
        Section {
            if lists.isEmpty {
                Text("Nothing loaded yet — check the server connection")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lists) { list in
                    Toggle(isOn: Binding(
                        get: { manager.isListVisible(list) },
                        set: { manager.setListVisible(list, $0) }
                    )) {
                        Text(verbatim: list.title)
                    }
                }
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                if !lists.isEmpty {
                    Button("Show all") { manager.setAllVisible(lists, true) }
                        .buttonStyle(.link)
                    Button("Hide all") { manager.setAllVisible(lists, false) }
                        .buttonStyle(.link)
                }
            }
        } footer: {
            Text("Completed, canceled and trashed projects are never shown.")
        }
    }

    private func test() {
        testing = true
        testResult = nil
        Task {
            do {
                let areas = try await ThingsClient().listContainers(tool: "things_list_areas", serverURL: serverURL, token: token)
                testResult = String(localized: "✓ Connected — \(areas.count) areas")
            } catch {
                testResult = "✗ \(error.localizedDescription)"
            }
            testing = false
        }
    }
}

struct ClipboardScreenshotsSettings: View {
    @Default(.clipboardHistoryLimit) private var clipboardLimit
    @Default(.screenshotsLimit) private var screenshotsLimit
    @ObservedObject private var screenshots = ScreenshotsManager.shared

    var body: some View {
        Form {
            Section("Clipboard") {
                Defaults.Toggle(key: .showClipboardTab) {
                    Text("Show Clipboard tab and record history")
                }
                Stepper(value: $clipboardLimit, in: 5...200, step: 5) {
                    Text("Keep last \(clipboardLimit) items")
                }
                Text("History lives in memory only and is cleared when the app quits. Passwords copied from password managers are skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Screenshots") {
                Defaults.Toggle(key: .showScreenshotsTab) {
                    Text("Show Screenshots tab")
                }
                HStack {
                    Group {
                        if let folder = screenshots.folderURL {
                            Text(verbatim: folder.path)
                        } else {
                            Text("No folder selected")
                        }
                    }
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") { screenshots.chooseFolder() }
                }
                Stepper(value: $screenshotsLimit, in: 3...50) {
                    Text("Show last \(screenshotsLimit) screenshots")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Clipboard & Screenshots")
    }
}

/// Used inside the original Calendar settings pane.
struct CalendarUpcomingDaysStepper: View {
    @Default(.calendarUpcomingDays) private var days

    var body: some View {
        Stepper(value: $days, in: 1...60) {
            Text("Upcoming events for \(days) days")
        }
    }
}
