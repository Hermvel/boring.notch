//
//  ThingsManager.swift
//  boringNotch
//
//  Holds the task lists shown in the Tasks tab and keeps them fresh:
//  refreshes on a timer and whenever the tab is opened.
//

import Foundation
import Combine
import Defaults

/// One selectable list in the Tasks tab.
struct ThingsList: Identifiable, Hashable {
    enum Kind: Hashable {
        case builtIn(tool: String)
        case area(uuid: String)
        case project(uuid: String)
    }

    let id: String
    let title: String
    let icon: String
    let kind: Kind

    static let today = ThingsList(id: "today", title: "Сегодня", icon: "star.fill", kind: .builtIn(tool: "things_list_today"))
    static let inbox = ThingsList(id: "inbox", title: "Входящие", icon: "tray", kind: .builtIn(tool: "things_list_inbox"))
    static let upcoming = ThingsList(id: "upcoming", title: "Планы", icon: "calendar", kind: .builtIn(tool: "things_list_upcoming"))
    static let anytime = ThingsList(id: "anytime", title: "В любое время", icon: "square.stack", kind: .builtIn(tool: "things_list_anytime"))
    static let someday = ThingsList(id: "someday", title: "Когда-нибудь", icon: "archivebox", kind: .builtIn(tool: "things_list_someday"))

    static let builtIns: [ThingsList] = [.today, .inbox, .upcoming, .anytime, .someday]

    static func area(_ c: ThingsContainer) -> ThingsList {
        ThingsList(id: "area:\(c.uuid)", title: c.title, icon: "square.3.layers.3d", kind: .area(uuid: c.uuid))
    }

    static func project(_ c: ThingsContainer) -> ThingsList {
        ThingsList(id: "project:\(c.uuid)", title: c.title, icon: "circle.dashed", kind: .project(uuid: c.uuid))
    }
}

@MainActor
final class ThingsManager: ObservableObject {
    static let shared = ThingsManager()

    @Published private(set) var areas: [ThingsList] = []
    @Published private(set) var projects: [ThingsList] = []
    @Published private(set) var tasks: [ThingsTask] = []
    @Published private(set) var selectedList: ThingsList = .today
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    /// Tasks ticked in this session — kept visible (struck through) until the next refresh,
    /// so a mis-click can be undone.
    @Published private(set) var recentlyCompleted: Set<String> = []

    private let client = ThingsClient()
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var loadGeneration = 0

    private var serverURL: String { Defaults[.thingsServerURL] }
    private var token: String { Defaults[.thingsAuthToken] }

    var allLists: [ThingsList] { ThingsList.builtIns + areas + projects }

    private init() {
        Defaults.publisher(.thingsRefreshMinutes, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleTimer() }
            .store(in: &cancellables)

        // Server address / token typed in Settings: wait until typing stops, then reload.
        Defaults.publisher(.thingsServerURL, options: []).map { _ in () }
            .merge(with: Defaults.publisher(.thingsAuthToken, options: []).map { _ in () })
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                Task { await self.reloadEverything() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    /// Called when the Tasks tab appears. Cheap to call repeatedly.
    func activate() {
        if refreshTimer == nil { scheduleTimer() }
        Task {
            if areas.isEmpty && projects.isEmpty { await loadContainers() }
            if selectedList.id != Defaults[.thingsLastListID],
               let saved = allLists.first(where: { $0.id == Defaults[.thingsLastListID] }) {
                selectedList = saved
            }
            await refresh()
        }
    }

    func reloadEverything() async {
        areas = []
        projects = []
        tasks = []
        await loadContainers()
        await refresh()
    }

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        let minutes = max(1, Defaults[.thingsRefreshMinutes])
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    // MARK: - Loading

    func select(_ list: ThingsList) {
        guard list != selectedList else { return }
        selectedList = list
        Defaults[.thingsLastListID] = list.id
        tasks = []
        Task { await refresh() }
    }

    func loadContainers() async {
        do {
            async let areaItems = client.listContainers(tool: "things_list_areas", serverURL: serverURL, token: token)
            async let projectItems = client.listContainers(tool: "things_list_projects", serverURL: serverURL, token: token)
            let (a, p) = try await (areaItems, projectItems)
            areas = a.map(ThingsList.area)
            projects = p.map(ThingsList.project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        loadGeneration += 1
        let generation = loadGeneration
        let list = selectedList
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }

        do {
            let result: [ThingsTask]
            switch list.kind {
            case .builtIn(let tool):
                result = try await client.listTasks(tool: tool, serverURL: serverURL, token: token)
            case .area(let uuid):
                result = try await client.listTasks(tool: "things_list_area_tasks", arguments: ["area_uuid": uuid], serverURL: serverURL, token: token)
            case .project(let uuid):
                result = try await client.listTasks(tool: "things_list_project_tasks", arguments: ["project_uuid": uuid], serverURL: serverURL, token: token)
            }
            // A newer request (e.g. user switched lists) already started — drop this answer.
            guard generation == loadGeneration else { return }
            tasks = result.filter(\.isOpen)
            recentlyCompleted = []
            errorMessage = nil
            lastUpdated = Date()
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Actions

    func toggleCompleted(_ task: ThingsTask) {
        let completing = !recentlyCompleted.contains(task.uuid)
        // Optimistic update: flip the checkbox now, roll back if the server refuses.
        if completing { recentlyCompleted.insert(task.uuid) } else { recentlyCompleted.remove(task.uuid) }

        Task {
            do {
                try await client.setCompleted(completing, uuid: task.uuid, serverURL: serverURL, token: token)
            } catch {
                if completing { recentlyCompleted.remove(task.uuid) } else { recentlyCompleted.insert(task.uuid) }
                errorMessage = error.localizedDescription
            }
        }
    }

    func projectTitle(for task: ThingsTask) -> String? {
        if let id = task.projectID, let p = projects.first(where: { $0.kind == .project(uuid: id) }) { return p.title }
        if let id = task.areaID, let a = areas.first(where: { $0.kind == .area(uuid: id) }) { return a.title }
        return nil
    }
}
