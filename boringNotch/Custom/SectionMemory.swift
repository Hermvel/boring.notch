//
//  SectionMemory.swift
//  boringNotch
//
//  Remembers the open section between notch openings:
//  reopening within `timeout` after the notch closed shows the same section,
//  after that it falls back to Home (music).
//

import Foundation

@MainActor
enum SectionMemory {
    static let timeout: TimeInterval = 3 * 60

    private static var lastClosedAt: Date?

    static func notchDidClose() {
        lastClosedAt = Date()
    }

    static func notchWillOpen(coordinator: BoringViewCoordinator) {
        guard let closedAt = lastClosedAt else { return }
        if Date().timeIntervalSince(closedAt) > timeout, coordinator.currentView != .home {
            coordinator.currentView = .home
        }
    }
}
