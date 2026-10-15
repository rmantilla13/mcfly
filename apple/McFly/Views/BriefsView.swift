import McFlyKit
import SwiftUI

/// Every brief, grouped by day, newest first.
struct BriefsView: View {
    @Environment(AppModel.self) private var app

    private var feeds: FeedStore { app.feeds }

    var body: some View {
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
                            BriefRow(brief: brief, agent: feeds.agent(brief.agentId))
                        }
                    }
                }
            }
        }
        .groupedList()
        .scrollContentBackground(.hidden)
        .screenBackground()
        .refreshable { await feeds.refresh() }
        .navigationTitle("Briefs")
        .navigationDestination(for: Brief.self) { BriefReaderView(brief: $0) }
    }
}

struct BriefRow: View {
    let brief: Brief
    let agent: Agent?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(brief.title)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Spacer()
                Text(Format.time(brief.publishedAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
            Text(BriefText.summary(brief.body))
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
            HStack(spacing: 8) {
                AgentBadge(agent: agent)
                Tag(text: brief.kind.label, color: agent.map { Color(hex: $0.color) } ?? Theme.accent)
            }
        }
        .padding(.vertical, 4)
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
