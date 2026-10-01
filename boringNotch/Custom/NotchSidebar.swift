//
//  NotchSidebar.swift
//  boringNotch
//
//  Vertical section list shown on the left of the open notch (1/5 of the width).
//  Replaces the small icon tabs that used to sit in the header.
//

import SwiftUI
import Defaults

struct NotchSidebar: View {
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @Default(.boringShelf) private var shelfEnabled
    @Default(.showTasksTab) private var tasksEnabled
    @Default(.showClipboardTab) private var clipboardEnabled
    @Default(.showScreenshotsTab) private var screenshotsEnabled
    @Default(.showCalendarSection) private var calendarEnabled
    @Namespace private var selection

    private struct SidebarItem: Identifiable {
        let view: NotchViews
        let title: String
        let icon: String
        var id: String { title }
    }

    private var sections: [SidebarItem] {
        var result = [SidebarItem(view: .home, title: "Главная", icon: "house.fill")]
        if shelfEnabled { result.append(SidebarItem(view: .shelf, title: "AirDrop", icon: "antenna.radiowaves.left.and.right")) }
        if tasksEnabled { result.append(SidebarItem(view: .tasks, title: "Задачи", icon: "checklist")) }
        if calendarEnabled { result.append(SidebarItem(view: .calendar, title: "Календарь", icon: "calendar")) }
        if clipboardEnabled || screenshotsEnabled {
            result.append(SidebarItem(view: .clipboard, title: "Буфер", icon: "doc.on.clipboard"))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(sections) { section in
                row(section)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func row(_ section: SidebarItem) -> some View {
        let selected = coordinator.currentView == section.view
        return Button {
            withAnimation(.smooth(duration: 0.25)) {
                coordinator.currentView = section.view
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: section.icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(section.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? .white : .gray)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .secondarySystemFill))
                        .matchedGeometryEffect(id: "sidebarSelection", in: selection)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
