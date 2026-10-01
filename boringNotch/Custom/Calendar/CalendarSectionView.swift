//
//  CalendarSectionView.swift
//  boringNotch
//
//  The "Календарь" section.
//  Left: month grid with ‹ › arrows (dots mark days with events, click a day to list from it).
//  Right: upcoming events grouped by day; click an event to open it in Calendar.
//

import SwiftUI
import EventKit
import Defaults

struct CalendarSectionView: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.calendarUpcomingDays) private var upcomingDays

    @State private var displayedMonth = Self.startOfMonth(Date())
    @State private var selectedDay: Date?
    @State private var daysWithEvents: Set<Date> = []
    @State private var upcoming: [EventModel] = []
    @State private var loading = false

    private static let calendar: Calendar = {
        var cal = Calendar.current
        cal.locale = Locale(identifier: "ru_RU")
        cal.firstWeekday = 2 // Monday
        return cal
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            monthGrid
                .frame(width: 190)
            Divider().opacity(0.3)
            upcomingList
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task {
            await calendarManager.checkCalendarAuthorization()
            await reload()
        }
        .onChange(of: displayedMonth) { Task { await reload() } }
        .onChange(of: selectedDay) { Task { await reload() } }
        .onChange(of: upcomingDays) { Task { await reload() } }
        .onChange(of: calendarManager.selectedCalendarIDs) { Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await reload() }
        }
    }

    // MARK: - Month grid

    private var monthGrid: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                Spacer(minLength: 0)
                Button {
                    withAnimation(.smooth(duration: 0.2)) {
                        displayedMonth = Self.startOfMonth(Date())
                        selectedDay = nil
                    }
                } label: {
                    Text(Self.monthTitle(displayedMonth))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help("К сегодняшнему дню")
                Spacer(minLength: 0)
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.gray)
            .frame(height: 16)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(day == "Сб" || day == "Вс" ? Color.gray.opacity(0.6) : .gray)
                        .frame(height: 12)
                }
            }

            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(gridDays(), id: \.self) { day in
                    dayCell(day)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let cal = Self.calendar
        let inMonth = cal.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isToday = cal.isDateInToday(day)
        let isSelected = selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
        let hasEvents = daysWithEvents.contains(cal.startOfDay(for: day))

        return Button {
            withAnimation(.smooth(duration: 0.15)) {
                selectedDay = isSelected ? nil : day
                if !inMonth { displayedMonth = Self.startOfMonth(day) }
            }
        } label: {
            ZStack {
                if isToday {
                    Circle().fill(Color.accentColor)
                } else if isSelected {
                    Circle().stroke(Color.white.opacity(0.7), lineWidth: 1)
                }
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 10, weight: isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isToday ? .white : (inMonth ? .white : Color.gray.opacity(0.45)))
                if hasEvents && !isToday {
                    Circle()
                        .fill(inMonth ? Color.accentColor : Color.gray.opacity(0.45))
                        .frame(width: 3, height: 3)
                        .offset(y: 7)
                }
            }
            .frame(width: 16, height: 16)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Always 6 weeks, Monday-first, so the grid height never jumps between months.
    private func gridDays() -> [Date] {
        let cal = Self.calendar
        let weekday = cal.component(.weekday, from: displayedMonth)
        let offset = (weekday - cal.firstWeekday + 7) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -offset, to: displayedMonth) else { return [] }
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = Self.calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        withAnimation(.smooth(duration: 0.2)) { displayedMonth = next }
    }

    // MARK: - Upcoming list

    @ViewBuilder
    private var upcomingList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(selectedDay.map { "С " + Self.shortDate($0) } ?? "Предстоящие")
                    .font(.system(size: 13, weight: .semibold))
                if selectedDay != nil {
                    Button {
                        withAnimation(.smooth(duration: 0.2)) { selectedDay = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.gray)
                    .help("Показать с сегодняшнего дня")
                }
                Spacer()
            }

            if calendarManager.calendarAuthorizationStatus == .denied || calendarManager.calendarAuthorizationStatus == .restricted {
                placeholder("Нет доступа к календарю — разрешите его в Системных настройках", icon: "lock")
            } else if upcoming.isEmpty {
                placeholder(loading ? "Загрузка…" : "Событий нет", icon: loading ? "hourglass" : "calendar")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                        ForEach(groupedUpcoming) { group in
                            Text(Self.dayHeader(group.day))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.gray)
                                .padding(.top, 4)
                            ForEach(group.events) { event in
                                EventRow(event: event)
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let events: [EventModel]
        var id: Date { day }
    }

    private var groupedUpcoming: [DayGroup] {
        let cal = Self.calendar
        let start = rangeStart
        let groups = Dictionary(grouping: upcoming) { event -> Date in
            // Multi-day events that started earlier are listed under the first shown day.
            max(cal.startOfDay(for: event.start), start)
        }
        return groups.keys.sorted().map { day in
            let events = (groups[day] ?? []).sorted { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                return a.start < b.start
            }
            return DayGroup(day: day, events: events)
        }
    }

    private var rangeStart: Date {
        Self.calendar.startOfDay(for: selectedDay ?? Date())
    }

    private func placeholder(_ text: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 18))
            Text(text)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.gray)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading

    private func reload() async {
        let cal = Self.calendar
        loading = true
        defer { loading = false }

        // Dots for the visible 6-week grid.
        let days = gridDays()
        if let first = days.first, let last = days.last, let end = cal.date(byAdding: .day, value: 1, to: last) {
            let monthEvents = await calendarManager.events(from: first, to: end)
            var marked = Set<Date>()
            for event in monthEvents where !isCompletedReminder(event) {
                var day = cal.startOfDay(for: event.start)
                let lastDay = cal.startOfDay(for: event.isAllDay ? event.end.addingTimeInterval(-1) : event.end)
                while day <= lastDay && day <= last {
                    marked.insert(day)
                    guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                }
            }
            daysWithEvents = marked
        }

        // Upcoming list: from the selected day (or today) for N days; hide what has already ended.
        let start = rangeStart
        guard let end = cal.date(byAdding: .day, value: max(1, upcomingDays), to: start) else { return }
        let now = Date()
        upcoming = await calendarManager.events(from: start, to: end)
            .filter { !isCompletedReminder($0) && $0.end > now }
    }

    private func isCompletedReminder(_ event: EventModel) -> Bool {
        if case .reminder(let completed) = event.type { return completed }
        return false
    }

    // MARK: - Formatting

    private static func startOfMonth(_ date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EE, d MMMM"
        return f
    }()

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM"
        return f
    }()

    static func monthTitle(_ date: Date) -> String {
        let title = monthFormatter.string(from: date)
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    static func shortDate(_ date: Date) -> String {
        shortDayFormatter.string(from: date)
    }

    static func dayHeader(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return "Сегодня" }
        if calendar.isDateInTomorrow(day) { return "Завтра" }
        let text = dayFormatter.string(from: day)
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

private struct EventRow: View {
    let event: EventModel
    @State private var hovering = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f
    }()

    private var timeText: String {
        if event.isAllDay { return "Весь день" }
        if case .reminder = event.type { return Self.timeFormatter.string(from: event.start) }
        return Self.timeFormatter.string(from: event.start) + "–" + Self.timeFormatter.string(from: event.end)
    }

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(nsColor: event.calendar.color))
                .frame(width: 3, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(timeText)
                    if let location = event.location, !location.isEmpty {
                        Text("· " + location).lineLimit(1)
                    }
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.gray)
            }
            Spacer(minLength: 0)
            if event.eventStatus == .inProgress {
                Text("сейчас")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.white.opacity(0.08) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if let url = event.calendarAppURL() { NSWorkspace.shared.open(url) }
        }
        .help(event.title)
    }
}
