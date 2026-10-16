import McFlyKit
import SwiftUI

/// Every brief, grouped by day, newest first. One from the last hour carries
/// a "new" dot (the insights' hour), so the list keeps a minute clock.
struct BriefsView: View {
    @Environment(AppModel.self) private var app

    private var feeds: FeedStore { app.feeds }

    var body: some View {
        TimelineView(.everyMinute) { context in
            list(now: context.date)
        }
        .screenBackground()
        .refreshable { await feeds.refresh() }
        .navigationTitle("Briefs")
        .navigationDestination(for: Brief.self) { BriefReaderView(brief: $0) }
    }

    private func list(now: Date) -> some View {
        List {
            if let message = feeds.errorMessage {
                ErrorBanner(message: message) { Task { await feeds.refresh() } }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            if feeds.briefs.isEmpty {
                EmptyCard(text: feeds.hasLoaded ? "No briefs yet. Agents push them with their key." : "Loading…",
                          systemImage: "text.alignleft")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            ForEach(feeds.briefsByDay(), id: \.day) { day in
                Section(Format.dayLabel(day.day)) {
                    ForEach(day.briefs) { brief in
                        NavigationLink(value: brief) {
                            BriefRow(brief: brief, agent: feeds.agent(brief.agentId), now: now)
                        }
                    }
                }
            }
        }
        .groupedList()
        .scrollContentBackground(.hidden)
    }
}

/// A brief in the list: its title (a dot when it's under an hour old), how
/// it opens, and who sent it. A brief that opens with `- ` points shows its
/// first two as bullets, as the reader lays them out.
struct BriefRow: View {
    let brief: Brief
    let agent: Agent?
    var now: Date = .now

    private var color: Color { agent.map { Color(hex: $0.color) } ?? Theme.accent }

    /// Under an hour old (and not stamped ahead of the clock): the insights' "fresh".
    private var isNew: Bool {
        let age = now.timeIntervalSince(brief.publishedAt)
        return age < Insights.briefFresh && age > -5 * 60
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if isNew {
                    NewDot(color: Theme.accent)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                }
                Text(brief.title)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Spacer()
                Text(Format.time(brief.publishedAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
            preview
            HStack(spacing: 8) {
                AgentBadge(agent: agent)
                Tag(text: brief.kind.label, color: color)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isNew ? "New" : "")
    }

    /// The opening paragraph, or the opening points as bullets.
    @ViewBuilder
    private var preview: some View {
        switch BriefText.blocks(brief.body).first {
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.prefix(2).enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(color)
                            .frame(width: 5, height: 5)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
            }
        case .paragraph(let text):
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
        case nil:
            EmptyView()
        }
    }
}

/// A brief's "new" dot: once, as it first shows, a ring spreads out from it
/// and fades (not with Reduce Motion on).
private struct NewDot: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pinged = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .background {
                Circle()
                    .stroke(color, lineWidth: 1.5)
                    .scaleEffect(pinged ? 2.6 : 1)
                    .opacity(pinged || reduceMotion ? 0 : 0.6)
            }
            .onAppear {
                guard !pinged, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.2).delay(0.2)) { pinged = true }
            }
            .accessibilityHidden(true)
    }
}

/// The whole brief, with its paragraphs and bullets laid out.
struct BriefReaderView: View {
    let brief: Brief
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    AgentBadge(agent: app.feeds.agent(brief.agentId))
                    Tag(text: brief.kind.label)
                    Spacer()
                }
                Text(brief.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(brief.publishedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                Divider()
                BriefBody(text: brief.body)
                    .lineSpacing(4)
                if let expires = brief.expiresAt {
                    Text("Expires \(expires.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 8)
                }
            }
            .padding(Theme.page)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle(brief.kind.label)
        .inlineTitle()
    }
}
