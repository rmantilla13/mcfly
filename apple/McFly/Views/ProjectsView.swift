import McFlyKit
import SwiftUI

/// What the agents say the person is working on, as the display's Projects
/// and the console's List lay it out: over it, where everything stands (a
/// bar split by status, and chips that show one group), then a group per
/// status, the one that needs you first (Blocked, Active, Paused, Up next,
/// Done, which stays folded until opened), a row per project. A row wears
/// its colour down its edge and says when it last moved, with its stages
/// as a bar (or its progress) and what's next. A blocked one has Ask why
/// under it, which asks McFly what would unblock it.
struct ProjectsView: View {
    @Environment(AppModel.self) private var app
    @State private var asking: String?

    private var feeds: FeedStore { app.feeds }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let message = feeds.errorMessage {
                    ErrorBanner(message: message) { Task { await feeds.refresh() } }
                }
                if feeds.projects.isEmpty {
                    EmptyCard(text: feeds.hasLoaded ? "No projects yet. A code or task agent pushes them." : "Loading…",
                              systemImage: "folder")
                } else {
                    ProjectList(projects: feeds.projects, agents: feeds.agents) { asking = $0 }
                }
            }
            .padding(Theme.page)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .refreshable { await feeds.refresh() }
        .navigationTitle("Projects")
        .navigationDestination(for: Project.self) { ProjectDetailView(project: $0) }
        .feedQuestion($asking)
    }

    /// "Why is Onyx blocked, and what would unblock it?": the console's Ask why.
    static func question(about project: Project) -> String {
        project.status == .blocked
            ? "Why is \(project.name) blocked, and what would unblock it?"
            : "Where does \(project.name) stand, and what's next?"
    }
}

/// One group: a status and its projects, in the agents' order.
private struct ProjectLane: Identifiable {
    let status: Project.Status
    let projects: [Project]
    var id: Project.Status { status }

    /// Every group, the one that needs you first. A status this version
    /// doesn't know has already decoded as active, so it joins Active, as on
    /// the console.
    static func lanes(_ projects: [Project]) -> [ProjectLane] {
        [Project.Status.blocked, .active, .paused, .planned, .done].map { status in
            ProjectLane(status: status, projects: projects.filter { $0.status == status })
        }
    }

    /// The console's dots: coral blocked, green active, amber paused,
    /// indigo up next, grey done.
    var color: Color {
        switch status {
        case .blocked: return Theme.down
        case .active: return Theme.up
        case .paused: return Theme.amber
        case .planned: return Color.planned
        case .done: return Theme.muted
        }
    }
}

/// The status card, then the groups (just the one picked, when a chip is).
/// Done stays folded under its header until opened, unless it's the chip.
private struct ProjectList: View {
    let projects: [Project]
    let agents: [Agent]
    let ask: (String) -> Void
    @State private var filter: Project.Status?
    @State private var showDone = false
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let lanes = ProjectLane.lanes(projects).filter { !$0.projects.isEmpty }
        // A chip whose group has emptied shows everything again.
        let showing = filter.flatMap { f in lanes.contains { $0.status == f } ? f : nil }
        // The agent's name only says something when there's more than one.
        let manyAgents = Set(projects.map(\.agentId)).count > 1
        let order = Dictionary(lanes.flatMap(\.projects).enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: 22) {
            ProjectStatusCard(lanes: lanes, total: projects.count, showing: showing) { status in
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { filter = showing == status ? nil : status }
            }
            ForEach(lanes.filter { showing == nil || $0.status == showing }) { lane in
                let open = lane.status != .done || showDone || showing == .done
                VStack(alignment: .leading, spacing: 10) {
                    header(lane, open: open, foldable: lane.status == .done && showing != .done)
                    if open {
                        group(lane, manyAgents: manyAgents, order: order)
                    }
                }
            }
        }
        .onAppear { revealed = true }
    }

    private func header(_ lane: ProjectLane, open: Bool, foldable: Bool) -> some View {
        HStack(spacing: 9) {
            Circle().fill(lane.color).frame(width: 9, height: 9)
            Text(lane.status == .blocked ? "Needs you" : lane.status.groupLabel)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.text)
            ProjectCount(count: lane.projects.count)
            Spacer()
            if foldable {
                Button(open ? "Hide" : "Show") {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { showDone.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The group's rows on one card, a hairline between them; Needs you's
    /// card is tinted coral and its edge breathes.
    private func group(_ lane: ProjectLane, manyAgents: Bool, order: [UUID: Int]) -> some View {
        let blocked = lane.status == .blocked
        let shape = RoundedRectangle(cornerRadius: Theme.radiusSm + 4, style: .continuous)
        return VStack(spacing: 0) {
            ForEach(Array(lane.projects.enumerated()), id: \.element.id) { index, project in
                if index > 0 {
                    Rectangle().fill(Theme.divider).frame(height: 1).padding(.leading, 30)
                }
                ProjectRow(project: project, agent: agents.first { $0.id == project.agentId }, showAgent: manyAgents, ask: ask)
                    .opacity(revealed || reduceMotion ? 1 : 0)
                    .offset(y: revealed || reduceMotion ? 0 : 10)
                    .animation(.smooth(duration: 0.38).delay(Double(min(order[project.id] ?? 0, 8)) * 0.035), value: revealed)
            }
        }
        .background(blocked ? Theme.coral.opacity(Theme.palette.isDark ? 0.12 : 0.08) : Theme.surface, in: shape)
        .overlay {
            if blocked {
                shape.strokeBorder(Theme.danger.opacity(0.7), lineWidth: 1.5)
                BoardBreath { phase in
                    shape.inset(by: 1.5).strokeBorder(Theme.danger.opacity(0.35 * (phase ?? 0)), lineWidth: 4)
                }
                .allowsHitTesting(false)
            }
        }
        .clipShape(shape)
        .shadow(color: .black.opacity(0.05), radius: 14, y: 4)
    }
}

/// Where everything stands: how many projects and how many need you, and a
/// bar split by status in the groups' colours, on a card; under it a chip
/// per status with its count (All first), scrolling to the screen's edge,
/// that shows just that group, and again shows all.
private struct ProjectStatusCard: View {
    let lanes: [ProjectLane]
    let total: Int
    let showing: Project.Status?
    let pick: (Project.Status?) -> Void

    var body: some View {
        let blocked = lanes.first { $0.status == .blocked }?.projects.count ?? 0
        let open = lanes.filter { $0.status != .done && $0.status != .planned }.reduce(0) { $0 + $1.projects.count }
        VStack(alignment: .leading, spacing: 12) {
            summary(blocked: blocked, open: open)
            chips
        }
    }

    private func summary(blocked: Int, open: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(total == 1 ? "1 project" : "\(total) projects")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Text("· \(open) in flight")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 8)
                if blocked > 0 {
                    Label(blocked == 1 ? "1 needs you" : "\(blocked) need you", systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.danger)
                        .labelStyle(.titleAndIcon)
                }
            }
            .contentTransition(.numericText())
            .accessibilityElement(children: .combine)
            GeometryReader { geo in
                let gaps = CGFloat(max(0, lanes.count - 1)) * 3
                HStack(spacing: 3) {
                    ForEach(lanes) { lane in
                        Capsule()
                            .fill(lane.color)
                            .opacity(showing == nil || showing == lane.status ? 1 : 0.3)
                            .frame(width: max(6, (geo.size.width - gaps) * CGFloat(lane.projects.count) / CGFloat(max(1, total))))
                    }
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
        .card()
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", count: total, color: nil, selected: showing == nil) { pick(nil) }
                ForEach(lanes) { lane in
                    chip(lane.status.groupLabel, count: lane.projects.count, color: lane.color, selected: showing == lane.status) {
                        pick(lane.status)
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, count: Int, color: Color?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let color {
                    Circle().fill(color).frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(selected ? Theme.text : Theme.muted)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(selected ? (color ?? Theme.accent).opacity(0.18) : Theme.text.opacity(0.06), in: Capsule())
            .overlay {
                if selected { Capsule().strokeBorder((color ?? Theme.accent).opacity(0.8), lineWidth: 1.5) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A group's count in a small pill.
private struct ProjectCount: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Theme.text.opacity(0.07), in: Capsule())
            .contentTransition(.numericText(value: Double(count)))
            .animation(.smooth, value: count)
    }
}

/// One project in its group, opening its page: its colour down the edge,
/// the name and when it last moved, whose it is (when there's more than one
/// agent), its stages as a bar or else its progress, and what's next (what
/// happened last, once it's done or when nobody said). A blocked one has
/// Ask why under it, beside the link rather than inside it, so a tap there
/// asks and doesn't open.
private struct ProjectRow: View {
    let project: Project
    let agent: Agent?
    let showAgent: Bool
    let ask: (String) -> Void

    /// The project's colour, else its agent's, else the accent.
    static func color(_ project: Project, agent: Agent?) -> Color {
        if let hex = project.color, !hex.isEmpty { return Color(hex: hex) }
        if let agent { return Color(hex: agent.color) }
        return Theme.accent
    }

    var body: some View {
        let color = Self.color(project, agent: agent)
        let done = project.status == .done
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: project) {
                HStack(alignment: .top, spacing: 12) {
                    Capsule()
                        .fill(color)
                        .frame(width: 4)
                        .frame(maxHeight: .infinity)
                        .opacity(done ? 0.5 : 1)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(project.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(done ? Theme.muted : Theme.text)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 6)
                            Text(Format.relative(project.lastUpdate?.happenedAt ?? project.updatedAt))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                                .fixedSize()
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.muted.opacity(0.6))
                        }
                        if showAgent, let agent {
                            Text(agent.name)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                                .padding(.top, -6)
                        }
                        if let track = project.stageTrack {
                            StageBar(track: track, color: color)
                        } else if let progress = project.progress, !done {
                            HStack(spacing: 10) {
                                ProgressBar(value: Double(progress) / 100, color: color)
                                Text("\(progress)%")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        said(done: done)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 14)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            if project.status == .blocked {
                FeedAskChip(title: "Ask why") { ask(ProjectsView.question(about: project)) }
                    .padding(.leading, 30)
                    .padding(.bottom, 14)
                    .padding(.top, -4)
            }
        }
    }

    /// "Next: …" while it's open; else the newest update, else the summary.
    @ViewBuilder private func said(done: Bool) -> some View {
        if !done, let next = project.nextStep, !next.isEmpty {
            Text("\(Text("Next:").fontWeight(.semibold)) \(next)")
                .font(.subheadline)
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        } else if let update = project.lastUpdate {
            Label {
                Text(update.text).lineLimit(2).multilineTextAlignment(.leading)
            } icon: {
                Image(systemName: update.kind.systemImage).font(.caption)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.muted)
        } else if !project.summary.isEmpty {
            Text(project.summary)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
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
        case .planned: return .planned
        case .done: return Theme.up
        }
    }

    /// Planned's indigo, the console's PLANNED_COLOR and the display's.
    static let planned = Color(red: 0x7C / 255, green: 0x8C / 255, blue: 0xF8 / 255)
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

// MARK: Detail

/// The project on a gradient tile with a big ring (the display's detail),
/// its stages as steps, what's next, Ask why and the link out; then its last month as a strip of
/// days and its updates as a timeline: a rail with a node per update, the
/// kind as its icon and colour, a line for each day, newest at the top (the
/// feed's newest five at once, then up to 200 from `admin_project_updates`).
struct ProjectDetailView: View {
    let project: Project
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var updates: [ProjectUpdate]
    @State private var revealed = false
    @State private var asking: String?

    init(project: Project) {
        self.project = project
        _updates = State(initialValue: project.updates)
    }

    var body: some View {
        // The feed's copy once a refresh has one, so the tile keeps up.
        let project = app.feeds.project(self.project.id) ?? self.project
        let agent = app.feeds.agent(project.agentId)
        let color = ProjectRow.color(project, agent: agent)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProjectHeroTile(project: project, agent: agent)
                if let track = project.stageTrack {
                    ProjectStages(track: track, color: color, since: project.timeInStage())
                }
                if let next = project.nextStep, !next.isEmpty, project.status != .done {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NEXT")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.accent)
                        Text(next)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { actions(project) }
                    VStack(alignment: .leading, spacing: 10) { actions(project) }
                }
                ProjectActivityStrip(updates: updates, color: color)
                SectionHeader("Updates") {
                    if !updates.isEmpty {
                        Text("\(updates.count)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.muted)
                            .contentTransition(.numericText(value: Double(updates.count)))
                            .animation(.smooth, value: updates.count)
                    }
                }
                if updates.isEmpty {
                    EmptyCard(text: "No updates yet.", systemImage: "clock")
                } else {
                    ProjectTimeline(updates: updates, color: color, revealed: revealed)
                }
                Text("Updated \(project.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .padding(Theme.page)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle(project.key)
        .inlineTitle()
        .onAppear { revealed = true }
        .task {
            if let all = try? await app.admin.projectUpdates(project.id, limit: 200) {
                updates = all
            }
        }
        .feedQuestion($asking)
    }

    @ViewBuilder
    private func actions(_ project: Project) -> some View {
        Button {
            asking = ProjectsView.question(about: project)
        } label: {
            Label(project.status == .blocked ? "Ask why" : "Ask McFly", systemImage: "sparkle")
                .padding(.vertical, 2)
        }
        .buttonStyle(.pill())
        if let url = project.url {
            Button {
                openURL(url)
            } label: {
                Label("Open \(url.host ?? "link")", systemImage: "safari")
                    .padding(.vertical, 2)
            }
            .buttonStyle(.pill(.neutral))
        }
    }
}

/// The project's head on a gradient tile: its status and agent, its name and
/// summary, and its progress as a big ring that sweeps in. Blocked is coral,
/// paused amber, done green; an active project wears its own colour.
private struct ProjectHeroTile: View {
    let project: Project
    let agent: Agent?

    private var base: Int {
        switch project.status {
        case .blocked: return 0xF07F5A
        case .paused: return 0xF6B94A
        case .planned: return 0x7C8CF8
        case .done: return 0x3DB37A
        case .active:
            if let hex = project.color, !hex.isEmpty { return Color.rgb(hex: hex) }
            return agent.map { Color.rgb(hex: $0.color) } ?? Theme.palette.accent
        }
    }

    var body: some View {
        GradientTile(base: base, rings: 1, ringBias: 0.85, seed: 4.2) { tile in
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.status.label.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(tile.inkMuted)
                        .lineLimit(1)
                    Text(project.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(tile.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if !project.summary.isEmpty {
                        Text(project.summary)
                            .font(.subheadline)
                            .foregroundStyle(tile.inkMuted)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Label([project.kind.rawValue.capitalized, agent?.name].compactMap { $0 }.joined(separator: " · "),
                          systemImage: project.kind.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tile.inkMuted)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                if let progress = project.progress {
                    BoardRing(value: Double(progress) / 100, color: tile.ink, track: tile.ink.opacity(0.16), lineWidth: 10, delay: 0.15) {
                        VStack(spacing: 0) {
                            Text("\(progress)%")
                                .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(tile.ink)
                                .contentTransition(.numericText(value: Double(progress)))
                            Text("done")
                                .font(.caption)
                                .foregroundStyle(tile.inkMuted)
                        }
                    }
                    .frame(width: 112, height: 112)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(progress) percent done")
                }
            }
            .padding(22)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: Stages

private extension StageTrack.State {
    /// A segment's or node's fill: the project's colour behind it and where it
    /// is, the lanes' coral while blocked and amber while paused, the rest a
    /// faint track.
    func fill(_ color: Color) -> Color {
        switch self {
        case .done, .current: return color
        case .blocked: return Theme.down
        case .paused: return Theme.amber
        case .next: return Theme.text.opacity(0.1)
        }
    }

    /// The words' ink: red while blocked, amber while paused.
    var ink: Color {
        switch self {
        case .blocked: return Theme.danger
        case .paused: return Theme.warningInk
        default: return Theme.text
        }
    }
}

/// A project's stages as a bar (the console's StageBar): the headline and its
/// place ("Blocked in App Review", "3 of 4") over a segment per stage, the
/// ones behind it in the project's colour, the one it is in taller (coral
/// while blocked, amber while paused). It grows in from the left once.
struct StageBar: View {
    let track: StageTrack
    let color: Color
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(track.headline)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(track.here?.state.ink ?? Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(track.position)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 4) {
                ForEach(track.steps, id: \.number) { step in
                    Capsule()
                        .fill(step.state.fill(color))
                        .opacity(step.state == .done ? 0.55 : 1)
                        .frame(maxWidth: .infinity)
                        .frame(height: step.number - 1 == track.index ? 10 : 6)
                }
            }
            .frame(height: 10)
            .scaleEffect(x: grown || reduceMotion ? 1 : 0.02, y: 1, anchor: .leading)
            .animation(.smooth(duration: 0.6).delay(0.2), value: grown)
        }
        .onAppear { grown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stages")
        .accessibilityValue("\(track.headline), \(track.position)")
    }
}

/// A project's stages as steps (the console's StageSteps): where it is and
/// for how long, its place, then a node per stage with its name, joined by a
/// line drawn in the project's colour once the next one is reached too. Done
/// stages are ticked, the one it is in is ringed (blocked and paused say so),
/// the rest numbered. Across where they fit, down the card where they don't.
private struct ProjectStages: View {
    let track: StageTrack
    let color: Color
    /// How long it has been in its stage ("5 days"), or empty.
    let since: String

    private static let node: CGFloat = 30
    private static let stepWidth: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("STAGES")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text(track.position)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.muted)
                }
                Text(since.isEmpty ? track.headline : "\(track.headline) for \(since)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(track.here?.state.ink ?? Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(track.steps, id: \.number) { across($0) }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(track.steps, id: \.number) { down($0) }
                }
            }
        }
        .card()
        .accessibilityElement(children: .contain)
    }

    private func isLast(_ step: StageTrack.Step) -> Bool { step.number == track.steps.count }

    /// The line on from a step: in the colour once the next stage is reached too.
    private func line(after step: StageTrack.Step) -> some View {
        let onward = !isLast(step) && track.steps[step.number].state != .next
        return Capsule().fill(onward ? color.opacity(0.55) : Theme.text.opacity(0.12))
    }

    private func across(_ step: StageTrack.Step) -> some View {
        VStack(spacing: 8) {
            node(step)
            words(step, alignment: .center)
        }
        .frame(minWidth: Self.stepWidth, maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            if !isLast(step) {
                GeometryReader { g in
                    line(after: step)
                        .frame(width: max(0, g.size.width - Self.node - 12), height: 2)
                        .offset(x: (g.size.width + Self.node) / 2 + 6, y: Self.node / 2 - 1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func down(_ step: StageTrack.Step) -> some View {
        HStack(alignment: .top, spacing: 12) {
            node(step)
            words(step, alignment: .leading)
                .padding(.top, 5)
            Spacer(minLength: 0)
        }
        .padding(.bottom, isLast(step) ? 0 : 14)
        .background(alignment: .topLeading) {
            if !isLast(step) {
                line(after: step)
                    .frame(width: 2)
                    .padding(.top, Self.node + 4)
                    .padding(.bottom, 4)
                    .padding(.leading, Self.node / 2 - 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func words(_ step: StageTrack.Step, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(step.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(step.state == .next ? Theme.muted : Theme.text)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .lineLimit(2)
            Text(step.word)
                .font(.caption.weight(step.state == .next || step.state == .done ? .regular : .semibold))
                .foregroundStyle(step.state == .current ? Theme.text : step.state == .next || step.state == .done ? Theme.muted : step.state.ink)
        }
        .padding(.horizontal, alignment == .center ? 4 : 0)
    }

    private func node(_ step: StageTrack.Step) -> some View {
        ZStack {
            switch step.state {
            case .done:
                Circle().fill(color.opacity(0.8))
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accentInk)
            case .current:
                Circle().fill(color)
                Circle().fill(Theme.accentInk).frame(width: 10, height: 10)
            case .blocked:
                Circle().fill(Theme.down)
                Image(systemName: "exclamationmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.accentInk)
            case .paused:
                Circle().fill(Theme.surface)
                Circle().strokeBorder(Theme.amber, lineWidth: 3)
                Image(systemName: "pause.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.warningInk)
            case .next:
                Circle().strokeBorder(Theme.text.opacity(0.12), lineWidth: 2)
                Text("\(step.number)").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.muted)
            }
        }
        .frame(width: Self.node, height: Self.node)
        .background {
            // The one it is in wears a soft ring.
            if step.number - 1 == track.index {
                Circle().fill(step.state.fill(color).opacity(0.22)).padding(-5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The last 30 days as a strip of cells, a day each in the project's colour,
/// taller and fuller the busier; today last. They rise in once.
private struct ProjectActivityStrip: View {
    let updates: [ProjectUpdate]
    let color: Color
    var days = 30
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Day: Hashable {
        let day: Date
        let count: Int
    }

    /// `days` calendar days ending today, oldest first, each with how many updates fell on it.
    static func days(_ times: [Date], count: Int, now: Date, calendar: Calendar = .current) -> [Day] {
        let today = calendar.startOfDay(for: now)
        var counts: [Date: Int] = [:]
        for time in times { counts[calendar.startOfDay(for: time), default: 0] += 1 }
        return (0..<max(1, count)).compactMap { i in
            calendar.date(byAdding: .day, value: i - (count - 1), to: today).map { Day(day: $0, count: counts[$0] ?? 0) }
        }
    }

    var body: some View {
        let cells = Self.days(updates.map(\.happenedAt), count: days, now: .now)
        let most = max(1, cells.map(\.count).max() ?? 1)
        let total = cells.reduce(0) { $0 + $1.count }
        let settled = grown || reduceMotion
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("ACTIVITY")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(total == 0 ? "Nothing in \(days) days" : "\(total == 1 ? "1 update" : "\(total) updates") in \(days) days")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .contentTransition(.numericText(value: Double(total)))
                    .animation(.smooth, value: total)
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(cells.enumerated()), id: \.element.day) { index, cell in
                    let share = Double(cell.count) / Double(most)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(cell.count > 0 ? color.opacity(0.35 + 0.65 * share) : Theme.text.opacity(0.08))
                        .frame(maxWidth: .infinity)
                        .frame(height: cell.count > 0 ? 12 + 28 * share : 6)
                        .scaleEffect(x: 1, y: settled ? 1 : 0.1, anchor: .bottom)
                        .animation(.smooth(duration: 0.4).delay(Double(index) * 0.008), value: grown)
                }
            }
            .frame(height: 40, alignment: .bottom)
            HStack {
                Text(cells.first.map { $0.day.formatted(.dateTime.month(.abbreviated).day()) } ?? "")
                Spacer()
                Text("Today")
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
        .card()
        .onAppear { grown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity")
        .accessibilityValue(Self.spoken(cells, total: total, days: days))
    }

    /// "12 updates in the last 30 days; most on Oct 14 (5)".
    static func spoken(_ cells: [Day], total: Int, days: Int) -> String {
        let head = "\(total == 1 ? "1 update" : "\(total) updates") in the last \(days) days"
        guard let busiest = cells.max(by: { $0.count < $1.count }), busiest.count > 0 else { return head }
        return head + "; most on \(busiest.day.formatted(.dateTime.month(.wide).day())), \(busiest.count)"
    }
}

/// The updates as a timeline: a rail down the left with a node per update,
/// its kind as the icon and colour, under a line for each day (Today,
/// Yesterday, then the date). The newest node is ringed in the project's
/// colour. Rows settle in once, a beat apart.
private struct ProjectTimeline: View {
    let updates: [ProjectUpdate]
    let color: Color
    let revealed: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct DayGroup {
        let day: Date
        let items: [ProjectUpdate]
    }

    /// Newest day first, newest first within it.
    private static func groups(_ updates: [ProjectUpdate], calendar: Calendar = .current) -> [DayGroup] {
        let sorted = updates.sorted { ($0.happenedAt, $0.id) > ($1.happenedAt, $1.id) }
        var out: [DayGroup] = []
        for update in sorted {
            let day = calendar.startOfDay(for: update.happenedAt)
            if let last = out.last, last.day == day {
                out[out.count - 1] = DayGroup(day: day, items: last.items + [update])
            } else {
                out.append(DayGroup(day: day, items: [update]))
            }
        }
        return out
    }

    var body: some View {
        let groups = Self.groups(updates)
        let order = Dictionary(groups.flatMap(\.items).enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newest = groups.first?.items.first?.id
        let now = Date()
        VStack(alignment: .leading, spacing: 2) {
            ForEach(groups, id: \.day) { group in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Theme.text.opacity(0.25))
                        .frame(width: 8, height: 8)
                        .frame(width: 22, height: 22)
                        .background(Theme.surface, in: Circle())
                        .frame(width: 36)
                    Text(Format.dayLabel(group.day, now: now).uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 6)
                .accessibilityAddTraits(.isHeader)
                ForEach(group.items) { update in
                    row(update, newest: update.id == newest, today: Calendar.current.isDate(update.happenedAt, inSameDayAs: now), now: now)
                        .opacity(revealed || reduceMotion ? 1 : 0)
                        .offset(y: revealed || reduceMotion ? 0 : 10)
                        .animation(.smooth(duration: 0.38).delay(Double(min(order[update.id] ?? 0, 8)) * 0.035), value: revealed)
                }
            }
        }
        // The rail, behind the nodes: each node's disc cuts it.
        .background(alignment: .leading) {
            Capsule()
                .fill(Theme.text.opacity(0.08))
                .frame(width: 2)
                .padding(.vertical, 14)
                .padding(.leading, 17)
        }
        .card()
    }

    private func row(_ update: ProjectUpdate, newest: Bool, today: Bool, now: Date) -> some View {
        let style = UpdateStyle(update.kind)
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Theme.surface)
                Circle().fill(style.fill)
                Image(systemName: style.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(style.ink)
            }
            .frame(width: 36, height: 36)
            .overlay {
                if newest { Circle().strokeBorder(color, lineWidth: 2) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(update.text)
                    .font(.callout)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Text(style.label)
                    Text("·")
                    Text(Format.time(update.happenedAt))
                    if today {
                        Text("·")
                        Text(Format.relative(update.happenedAt, now: max(now, update.happenedAt)))
                    }
                    if let link = update.link {
                        Button {
                            openURL(link)
                        } label: {
                            Label(link.host ?? "Open", systemImage: "arrow.up.right")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .padding(.leading, 4)
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            }
            .padding(.top, 7)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

/// How each kind of update looks on the timeline (the console's ProjectTimeline).
private struct UpdateStyle {
    let label: String
    let icon: String
    let fill: Color
    let ink: Color

    init(_ kind: ProjectUpdate.Kind) {
        switch kind {
        case .commit:
            self.init(label: "Commit", icon: "arrow.triangle.branch", tint: Theme.blue)
        case .pr:
            self.init(label: "Pull request", icon: "arrow.triangle.pull", tint: Color(rgb: 0x7A64E8))
        case .ci:
            self.init(label: "CI", icon: "checkmark.seal.fill", tint: Theme.success)
        case .deploy:
            self.init(label: "Deploy", icon: "shippingbox.fill", tint: Color(rgb: 0x14A3B8))
        case .alert:
            self.init(label: "Alert", icon: "exclamationmark.triangle.fill", tint: Theme.danger)
        case .done:
            self.init(label: "Done", icon: "flag.fill", fill: Theme.success, ink: .white)
        case .note:
            self.init(label: "Note", icon: "text.bubble.fill", fill: Theme.sunken, ink: Theme.muted)
        }
    }

    private init(label: String, icon: String, tint: Color) {
        self.init(label: label, icon: icon, fill: tint.opacity(0.15), ink: tint)
    }

    private init(label: String, icon: String, fill: Color, ink: Color) {
        self.label = label
        self.icon = icon
        self.fill = fill
        self.ink = ink
    }
}
