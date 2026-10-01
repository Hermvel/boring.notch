//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI
import Defaults

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Tasks", icon: "checklist", view: .tasks),
    TabModel(label: "Calendar", icon: "calendar", view: .calendar),
    TabModel(label: "Clipboard", icon: "doc.on.clipboard", view: .clipboard)
]

/// Tabs hidden in Settings are skipped.
private func isTabEnabled(_ view: NotchViews) -> Bool {
    switch view {
    case .home: return true
    case .shelf: return Defaults[.boringShelf]
    case .tasks: return Defaults[.showTasksTab]
    case .calendar: return Defaults[.showCalendarSection]
    case .clipboard: return Defaults[.showClipboardTab] || Defaults[.showScreenshotsTab]
    }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation
    @Default(.boringShelf) private var shelfEnabled
    @Default(.showTasksTab) private var tasksEnabled
    @Default(.showClipboardTab) private var clipboardEnabled
    @Default(.showScreenshotsTab) private var screenshotsEnabled

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.filter { isTabEnabled($0.view) }) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
