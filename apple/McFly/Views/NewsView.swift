import McFlyKit
import SwiftUI

/// The newest Pulse report by section, with a picker for older ones.
struct NewsView: View {
    @Environment(AppModel.self) private var app
    @State private var chosenId: UUID?

    private var feeds: FeedStore { app.feeds }
    private var report: NewsReport? { feeds.report(chosenId) ?? feeds.latestReport }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let message = feeds.errorMessage {
                    ErrorBanner(message: message) { Task { await feeds.refresh() } }
                }
                if let report {
                    reportHeader(report)
                    if let hero = report.hero {
                        NavigationLink(value: hero) { HeroStoryCard(item: hero) }
                            .buttonStyle(PressableStyle())
                    }
                    ForEach(report.sections) { section in
                        SectionHeader(section.name)
                        ForEach(section.items) { item in
                            NavigationLink(value: item) { StoryCard(item: item) }
                                .buttonStyle(PressableStyle())
                        }
                    }
                } else {
                    EmptyCard(text: feeds.hasLoaded ? "No report yet. The Daily Pulse pipeline pushes one a day." : "Loading…",
                              systemImage: "newspaper")
                }
            }
            .padding(Theme.page)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .refreshable { await feeds.refresh() }
        .navigationTitle("News")
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Report", selection: Binding(get: { report?.id }, set: { chosenId = $0 })) {
                        ForEach(feeds.reports) { r in
                            Text(r.displayDate ?? r.reportDate).tag(Optional(r.id))
                        }
                    }
                } label: {
                    Label("Older reports", systemImage: "calendar")
                }
                .disabled(feeds.reports.count < 2)
            }
        }
        .navigationDestination(for: NewsItem.self) { StoryDetailView(item: $0) }
    }

    private func reportHeader(_ report: NewsReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DAILY PULSE")
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline) {
                Text(report.displayDate ?? report.reportDate)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("\(report.items.count) stories")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            AgentBadge(agent: feeds.agent(report.agentId))
        }
    }
}

/// Thumbnail, headline, takeaway.
struct StoryCard: View {
    let item: NewsItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StoryImage(url: item.image, height: 72)
                .frame(width: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if !item.takeaway.isEmpty {
                    Text(item.takeaway)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Text(item.source)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 10, radius: Theme.radiusSm)
    }
}

/// The story's picture, takeaway and source, and the link out.
struct StoryDetailView: View {
    let item: NewsItem
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StoryImage(url: item.image, height: 220)
                Tag(text: item.sectionName, color: Theme.coral)
                Text(item.headline)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                if !item.takeaway.isEmpty {
                    Text(item.takeaway)
                        .font(.body)
                        .foregroundStyle(Theme.text.opacity(0.9))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
                HStack(spacing: 6) {
                    Image(systemName: "link").font(.caption)
                    Text(item.source).font(.footnote)
                }
                .foregroundStyle(Theme.muted)
                if let link = item.link {
                    Button {
                        openURL(link)
                    } label: {
                        Label("Open Link", systemImage: "safari")
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
        .navigationTitle(item.sectionName)
        .inlineTitle()
    }
}
