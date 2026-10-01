//
//  CustomSettingsViews.swift
//  boringNotch
//
//  Settings panes for the custom tabs, plugged into SettingsView's sidebar.
//

import SwiftUI
import Defaults

struct TasksSettings: View {
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
        }
        .formStyle(.grouped)
        .navigationTitle("Tasks")
    }

    private func test() {
        testing = true
        testResult = nil
        Task {
            do {
                let areas = try await ThingsClient().listContainers(tool: "things_list_areas", serverURL: serverURL, token: token)
                testResult = "✓ Connected — \(areas.count) areas"
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
                    Text(screenshots.folderURL?.path ?? "No folder selected")
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
