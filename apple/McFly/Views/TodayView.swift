import McFlyKit
import SwiftUI

/// The latest brief, the quotes strip, and the newest Pulse report's top stories.
struct TodayView: View {
    @Environment(AppModel.self) private var app

    private var feeds: FeedStore { app.feeds }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let message = feeds.errorMessage {
                    ErrorBanner(message: message) { Task { await feeds.refresh() } }
                }
                briefSection
                projectsSection
                quotesSection
                upNextSection
                newsSection
            }
            .padding(.horizontal, Theme.page)
            .padding(.bottom, 32)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .refreshable { await feeds.refresh() }
        .navigationTitle("Today")
        .inlineTitle()
        .toolbar {
            #if os(macOS)
            ToolbarItem {
                Button { Task { await feeds.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(feeds.isLoading)
            }
            #endif
        }
        .navigationDestination(for: Brief.self) { BriefReaderView(brief: $0) }
        .navigationDestination(for: QuoteSeries.self) { SymbolDetailView(series: $0) }
        .navigationDestination(for: NewsItem.self) { StoryDetailView(item: $0) }
        .navigationDestination(for: CalendarEvent.self) { EventDetailView(event: $0) }
        .navigationDestination(for: Project.self) { ProjectDetailView(project: $0) }
    }

    @ViewBuilder
    private var projectsSection: some View {
        if !feeds.projects.isEmpty {
            SectionHeader("Projects")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(feeds.projectsByAttention) { project in
                        NavigationLink(value: project) {
                            ProjectCard(project: project, compact: true)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, Theme.page)
            }
            .padding(.horizontal, -Theme.page)
        }
    }

    @ViewBuilder
    private var upNextSection: some View {
        let next = feeds.upcomingEvents(limit: 3)
        if !next.isEmpty {
            SectionHeader("Up next")
            VStack(spacing: 8) {
                ForEach(next) { event in
                    NavigationLink(value: event) { EventRow(event: event, day: event.startsAt) }
                        .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.muted)
            Text(feeds.displayName)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var briefSection: some View {
        SectionHeader("Latest brief")
        if let brief = feeds.latestBrief {
            NavigationLink(value: brief) {
                BriefCard(brief: brief, agent: feeds.agent(brief.agentId), lines: 4)
            }
            .buttonStyle(PressableStyle())
        } else {
            EmptyCard(text: feeds.hasLoaded ? "No briefs yet. An agent pushes them." : "Loading…", systemImage: "text.alignleft")
        }
    }

    @ViewBuilder
    private var quotesSection: some View {
        SectionHeader("Markets")
        if feeds.series.isEmpty {
            EmptyCard(text: "No quotes yet.", systemImage: "chart.line.uptrend.xyaxis")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(feeds.series) { series in
                        NavigationLink(value: series) {
                            QuoteChip(series: series)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, Theme.page)
            }
            .padding(.horizontal, -Theme.page)
        }
    }

    @ViewBuilder
    private var newsSection: some View {
        if let report = feeds.latestReport {
            SectionHeader("Daily Pulse") {
                Text(report.displayDate ?? report.reportDate)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            if let hero = report.hero {
                NavigationLink(value: hero) {
                    HeroStoryCard(item: hero)
                }
                .buttonStyle(PressableStyle())
            }
            VStack(spacing: 8) {
                ForEach(report.headlines.prefix(4)) { item in
                    NavigationLink(value: item) {
                        HeadlineRow(item: item)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        } else {
            SectionHeader("Daily Pulse")
            EmptyCard(text: "No report yet.", systemImage: "newspaper")
        }
    }
}

/// Title, body preview, agent and time.
struct BriefCard: View {
    let brief: Brief
    let agent: Agent?
    var lines = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Tag(text: brief.kind.label, color: agent.map { Color(hex: $0.color) } ?? Theme.accent)
                Spacer()
                Text(Format.relative(brief.publishedAt))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            Text(brief.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.leading)
            Text(brief.body)
                .font(.subheadline)
                .foregroundStyle(Theme.text.opacity(0.85))
                .lineLimit(lines)
                .multilineTextAlignment(.leading)
            AgentBadge(agent: agent)
        }
        .card()
    }
}

/// Symbol, price and the colored change, for the Today strip.
struct QuoteChip: View {
    let series: QuoteSeries

    var body: some View {
        let quote = series.latest
        VStack(alignment: .leading, spacing: 4) {
            Text(series.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.muted)
            Text(Format.price(quote.price, currency: quote.currency))
                .font(.headline.monospacedDigit())
                .foregroundStyle(Theme.text)
            Text(Format.percent(quote.changePct))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.change(quote.changePct))
        }
        .frame(width: 110, alignment: .leading)
        .card(padding: 12, radius: Theme.radiusSm)
    }
}

/// The hero story: picture, section, headline.
struct HeroStoryCard: View {
    let item: NewsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StoryImage(url: item.image, height: 170)
            Tag(text: item.sectionName, color: Theme.coral)
            Text(item.headline)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.leading)
            Text(item.source)
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .card(padding: 12)
    }
}

struct HeadlineRow: View {
    let item: NewsItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.amber)
                .frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(item.sectionName) · \(item.source)")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 12, radius: Theme.radiusSm)
    }
}
