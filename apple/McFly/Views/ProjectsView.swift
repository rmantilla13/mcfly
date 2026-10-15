import McFlyKit
import SwiftUI

/// What the agents say the person is working on: a card per project.
struct ProjectsView: View {
    @Environment(AppModel.self) private var app

    private var feeds: FeedStore { app.feeds }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let message = feeds.errorMessage {
                    ErrorBanner(message: message) { Task { await feeds.refresh() } }
                }
                if feeds.projects.isEmpty {
                    EmptyCard(text: feeds.hasLoaded ? "No projects yet. A code or task agent pushes them." : "Loading…",
                              systemImage: "folder")
                } else {
                    ForEach(feeds.projects) { project in
                        NavigationLink(value: project) {
                            ProjectCard(project: project)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .padding(Theme.page)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .refreshable { await feeds.refresh() }
        .navigationTitle("Projects")
        .navigationDestination(for: Project.self) { ProjectDetailView(project: $0) }
    }
}

/// Name, status pill, progress, summary, next step and the last update.
struct ProjectCard: View {
    let project: Project
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: project.kind.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(project.color.map { Color(hex: $0) } ?? Theme.accent)
                Text(project.name)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer()
                StatusPill(status: project.status)
            }
            if let progress = project.progress {
                ProgressBar(value: Double(progress) / 100, color: Color.status(project.status))
                    .frame(maxWidth: compact ? 140 : .infinity)
            }
            if !compact {
                if !project.summary.isEmpty {
                    Text(project.summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.text.opacity(0.85))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                if let next = project.nextStep, !next.isEmpty {
                    Label(next, systemImage: "arrow.turn.down.right")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            if let update = project.lastUpdate {
                HStack(spacing: 6) {
                    Image(systemName: update.kind.systemImage).font(.caption2)
                    Text(update.text).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Format.relative(update.happenedAt))
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: compact ? 220 : nil, alignment: .leading)
        .card(padding: 14, radius: compact ? Theme.radiusSm : Theme.radius)
    }
}

struct StatusPill: View {
    let status: Project.Status

    var body: some View {
        Tag(text: status.label, color: Color.status(status))
    }
}

extension Color {
    static func status(_ status: Project.Status) -> Color {
        switch status {
        case .active: return Theme.accent
        case .blocked: return Theme.down
        case .paused: return Theme.amber
        case .done: return Theme.up
        }
    }
}

/// Thin rounded progress bar.
struct ProgressBar: View {
    let value: Double
    var color: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.sunken)
                Capsule().fill(color).frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: 8)
        .animation(Theme.springy, value: value)
        .accessibilityLabel("\(Int(value * 100)) percent")
    }
}

/// The project, its timeline (the feed's newest updates, then the whole list
/// from `admin_project_updates`), and the link out.
struct ProjectDetailView: View {
    let project: Project
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var updates: [ProjectUpdate] = []
    @State private var loadedAll = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    AgentBadge(agent: app.feeds.agent(project.agentId))
                    Tag(text: project.kind.rawValue)
                    StatusPill(status: project.status)
                }
                Text(project.name)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                if let progress = project.progress {
                    HStack(spacing: 10) {
                        ProgressBar(value: Double(progress) / 100, color: Color.status(project.status))
                        Text("\(progress)%").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.muted)
                    }
                }
                if !project.summary.isEmpty {
                    Text(project.summary).font(.body).foregroundStyle(Theme.text).textSelection(.enabled)
                }
                if let next = project.nextStep, !next.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NEXT STEP").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                        Text(next).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                    }
                    .card(padding: 14, radius: Theme.radiusSm)
                }
                if let url = project.url {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open \(url.host ?? "link")", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.pill())
                }
                timeline
                Text("Updated \(project.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .padding(Theme.page)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle(project.key)
        .inlineTitle()
        .task {
            updates = project.updates
            if let all = try? await app.admin.projectUpdates(project.id, limit: 50) {
                updates = all
                loadedAll = true
            }
        }
    }

    @ViewBuilder
    private var timeline: some View {
        SectionHeader("Updates")
        if updates.isEmpty {
            EmptyCard(text: "No updates yet.", systemImage: "clock")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(updates.enumerated()), id: \.element.id) { index, update in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Image(systemName: update.kind.systemImage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(update.kind == .alert ? Theme.down : Theme.accent)
                                .frame(width: 26, height: 26)
                                .background(Theme.sunken, in: Circle())
                            if index < updates.count - 1 {
                                Rectangle().fill(Theme.divider).frame(width: 2).frame(maxHeight: .infinity)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(update.text)
                                .font(.subheadline)
                                .foregroundStyle(Theme.text)
                                .textSelection(.enabled)
                            HStack(spacing: 8) {
                                Text(update.happenedAt.formatted(date: .abbreviated, time: .shortened))
                                if let link = update.link {
                                    Button(link.host ?? "Open") { openURL(link) }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                        }
                        .padding(.bottom, 16)
                        Spacer(minLength: 0)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
        }
    }
}
