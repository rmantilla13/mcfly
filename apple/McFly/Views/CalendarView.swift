import McFlyKit
import SwiftUI

/// A month grid and, under it, the agenda: events by day for the weeks ahead.
struct CalendarView: View {
    @Environment(AppModel.self) private var app
    @State private var month: Date = Calendar.current.startOfDay(for: .now)
    @State private var picked: Date?

    private var feeds: FeedStore { app.feeds }
    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let message = feeds.errorMessage {
                    ErrorBanner(message: message) { Task { await feeds.refresh() } }
                }
                MonthGrid(month: month, picked: $picked, events: feeds.events) { step in
                    if let next = calendar.date(byAdding: .month, value: step, to: month) {
                        withAnimation(Theme.springy) { month = next }
                    }
                }
                .card(padding: 12)
                if let picked {
                    let dayEvents = feeds.events(on: picked)
                    SectionHeader(Format.dayLabel(picked)) {
                        Button("Show all") { self.picked = nil }.buttonStyle(.pill(.soft))
                    }
                    if dayEvents.isEmpty {
                        EmptyCard(text: "Nothing on this day.", systemImage: "calendar")
                    } else {
                        ForEach(dayEvents) { event in
                            NavigationLink(value: event) { EventRow(event: event, day: picked) }
                                .buttonStyle(PressableStyle())
                        }
                    }
                } else {
                    let agenda = feeds.eventsByDay()
                    if agenda.isEmpty {
                        EmptyCard(text: feeds.hasLoaded ? "No events ahead. A calendar agent pushes them." : "Loading…",
                                  systemImage: "calendar")
                    }
                    ForEach(agenda, id: \.day) { day in
                        SectionHeader(Format.dayLabel(day.day))
                        ForEach(day.events) { event in
                            NavigationLink(value: event) { EventRow(event: event, day: day.day) }
                                .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
            .padding(Theme.page)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .refreshable { await feeds.refresh() }
        .navigationTitle("Calendar")
        .navigationDestination(for: CalendarEvent.self) { EventDetailView(event: $0) }
    }
}

/// Seven columns of days with a dot per event, colored by its calendar.
struct MonthGrid: View {
    let month: Date
    @Binding var picked: Date?
    let events: [CalendarEvent]
    let step: (Int) -> Void
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                Button { step(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 4)
            let symbols = calendar.veryShortStandaloneWeekdaySymbols
            let first = calendar.firstWeekday - 1
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(symbols[(first + i) % 7])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            let cells = Self.cells(for: month, calendar: calendar)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(cells, id: \.self) { cell in
                    if let day = cell.day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isPicked = picked.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let colors = Array(Set(events.filter { $0.occurs(on: day, calendar: calendar) }.map { $0.color ?? "#5B7CF5" })).sorted().prefix(3)
        return Button {
            picked = isPicked ? nil : day
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.footnote.weight(isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isPicked ? .white : (isToday ? Theme.accent : Theme.text))
                HStack(spacing: 2) {
                    ForEach(Array(colors), id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(isPicked ? Theme.accent : (isToday ? Theme.accentSoft : .clear),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
    }

    struct Cell: Hashable {
        let index: Int
        let day: Date?
    }

    /// Leading blanks so the 1st lands under its weekday, then every day of the month.
    static func cells(for month: Date, calendar: Calendar) -> [Cell] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells = (0..<leading).map { Cell(index: $0, day: nil) }
        for day in days {
            cells.append(Cell(index: cells.count, day: calendar.date(byAdding: .day, value: day - 1, to: interval.start)))
        }
        return cells
    }
}

/// Time (or All day), title, place; a bar in the calendar's color.
struct EventRow: View {
    let event: CalendarEvent
    var day: Date? = nil

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(hex: event.color ?? "#5B7CF5"))
                .frame(width: 5, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(Format.eventTime(event, on: day))
                    if let location = event.location, !location.isEmpty {
                        Text("·")
                        Text(location).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Text(event.calendar)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(hex: event.color ?? "#5B7CF5"))
        }
        .card(padding: 12, radius: Theme.radiusSm)
    }
}

struct EventDetailView: View {
    let event: CalendarEvent
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Tag(text: event.calendar, color: Color(hex: event.color ?? "#5B7CF5"))
                    AgentBadge(agent: app.feeds.agent(event.agentId))
                }
                Text(event.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                VStack(alignment: .leading, spacing: 8) {
                    Label(Format.eventSpan(event), systemImage: "clock")
                    if let location = event.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.text)
                .card(padding: 14, radius: Theme.radiusSm)
                if let description = event.description, !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(Theme.text.opacity(0.9))
                        .textSelection(.enabled)
                }
                if let link = event.link {
                    Button {
                        openURL(link)
                    } label: {
                        Label("Open \(link.host ?? "link")", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.pill())
                }
            }
            .padding(Theme.page)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle(Format.dayLabel(event.startsAt))
        .inlineTitle()
    }
}

extension Format {
    /// "All day", "2:30 PM", or "2:30 – 3:00 PM"; a multi-day event's edge days say "Until 5 PM" / "From 9 AM".
    static func eventTime(_ event: CalendarEvent, on day: Date? = nil, calendar: Calendar = .current) -> String {
        if event.allDay { return "All day" }
        if let day {
            let startsThisDay = calendar.isDate(event.startsAt, inSameDayAs: day)
            let endsThisDay = calendar.isDate(event.endsAt, inSameDayAs: day)
            if !startsThisDay && endsThisDay { return "Until \(time(event.endsAt))" }
            if startsThisDay && !endsThisDay { return "From \(time(event.startsAt))" }
            if !startsThisDay && !endsThisDay { return "All day" }
        }
        return "\(time(event.startsAt)) – \(time(event.endsAt))"
    }

    /// "Tuesday, Oct 14 · 2:30 – 3:00 PM", or the two dates for a multi-day event.
    static func eventSpan(_ event: CalendarEvent, calendar: Calendar = .current) -> String {
        let sameDay = calendar.isDate(event.startsAt, inSameDayAs: event.endsAt)
            || (event.allDay && calendar.isDate(event.startsAt, inSameDayAs: event.endsAt.addingTimeInterval(-1)))
        let day = event.startsAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        if sameDay { return "\(day) · \(eventTime(event))" }
        let end = event.endsAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return event.allDay ? "\(day) – \(end)" : "\(day) \(time(event.startsAt)) – \(end) \(time(event.endsAt))"
    }
}
