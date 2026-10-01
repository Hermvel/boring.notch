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

struct ThingsTag: Identifiable, Hashable {
    let id: String
    let name: String
}

@MainActor
final class ThingsManager: ObservableObject {
    static let shared = ThingsManager()

    /// Every open area/project from the server (Settings shows these with on/off toggles).
    @Published private(set) var allAreas: [ThingsList] = []
    @Published private(set) var allProjects: [ThingsList] = []
    @Published private(set) var hiddenListIDs: Set<String> = Set(Defaults[.thingsHiddenListIDs])

    /// What the list picker in the notch offers: open and not hidden in Settings.
    var areas: [ThingsList] { allAreas.filter { !hiddenListIDs.contains($0.id) } }
    var projects: [ThingsList] { allProjects.filter { !hiddenListIDs.contains($0.id) } }

    func isListVisible(_ list: ThingsList) -> Bool { !hiddenListIDs.contains(list.id) }

    func setListVisible(_ list: ThingsList, _ visible: Bool) {
        if visible { hiddenListIDs.remove(list.id) } else { hiddenListIDs.insert(list.id) }
        Defaults[.thingsHiddenListIDs] = hiddenListIDs.sorted()
    }

    func setAllVisible(_ lists: [ThingsList], _ visible: Bool) {
        for list in lists {
            if visible { hiddenListIDs.remove(list.id) } else { hiddenListIDs.insert(list.id) }
        }
        Defaults[.thingsHiddenListIDs] = hiddenListIDs.sorted()
    }
    @Published private(set) var tasks: [ThingsTask] = []
    @Published private(set) var selectedList: ThingsList = .today
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    /// Tasks ticked in this session — kept visible (struck through) until the next refresh,
    /// so a mis-click can be undone.
    @Published private(set) var recentlyCompleted: Set<String> = []

    /// Tag id → tag name, loaded once with areas/projects.
    @Published private(set) var tagNames: [String: String] = [:]
    /// Tags picked in the filter row; empty = show everything.
    @Published var selectedTags: Set<String> = []

    /// Tasks after the tag filter (a task matches if it has any of the selected tags).
    var visibleTasks: [ThingsTask] {
        guard !selectedTags.isEmpty else { return tasks }
        return tasks.filter { !selectedTags.isDisjoint(with: $0.tags ?? []) }
    }

    /// Tags that actually occur in the current list, most used first.
    var availableTags: [ThingsTag] {
        var counts: [String: Int] = [:]
        for task in tasks { for tag in task.tags ?? [] { counts[tag, default: 0] += 1 } }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : (tagNames[$0.key] ?? "") < (tagNames[$1.key] ?? "") }
            .compactMap { entry in tagNames[entry.key].map { ThingsTag(id: entry.key, name: $0) } }
    }

    func toggleTag(_ id: String) {
        if selectedTags.contains(id) { selectedTags.remove(id) } else { selectedTags.insert(id) }
    }

    private let client = ThingsClient()
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var loadGeneration = 0

    private var serverURL: String { Defaults[.thingsServerURL] }
    private var token: String { Defaults[.thingsAuthToken] }

    var allLists: [ThingsList] { ThingsList.builtIns + allAreas + allProjects }

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
            if allAreas.isEmpty && allProjects.isEmpty { await loadContainers() }
            if selectedList.id != Defaults[.thingsLastListID],
               let saved = allLists.first(where: { $0.id == Defaults[.thingsLastListID] }) {
                selectedList = saved
            }
            await refresh()
        }
    }

    func reloadEverything() async {
        allAreas = []
        allProjects = []
        tasks = []
        tagNames = [:]
        selectedTags = []
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
        selectedTags = []
        Task { await refresh() }
    }

    func loadContainers() async {
        do {
            async let areaItems = client.listContainers(tool: "things_list_areas", serverURL: serverURL, token: token)
            async let projectItems = client.listContainers(tool: "things_list_projects", serverURL: serverURL, token: token)
            async let tagItems = client.listContainers(tool: "things_list_tags", serverURL: serverURL, token: token)
            let (a, p, t) = try await (areaItems, projectItems, tagItems)
            allAreas = a.map(ThingsList.area)
            // Completed and trashed projects are already excluded by the server; canceled ones are not.
            allProjects = p.filter(\.isOpen).map(ThingsList.project)
            tagNames = Dictionary(t.map { ($0.uuid, $0.title) }, uniquingKeysWith: { first, _ in first })
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
            // Drop filter tags that no longer occur in this list.
            let present = Set(tasks.flatMap { $0.tags ?? [] })
            selectedTags.formIntersection(present)
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
        if let id = task.projectID, let p = allProjects.first(where: { $0.kind == .project(uuid: id) }) { return p.title }
        if let id = task.areaID, let a = allAreas.first(where: { $0.kind == .area(uuid: id) }) { return a.title }
        return nil
    }
}
