import McFlyKit
import SwiftUI

/// The dashboard builder, the console's (Feed → Dashboards → New dashboard)
/// the app's way: pick a template, then for each part of the board choose
/// where it pulls from (which symbols, metrics, projects, calendars,
/// agents…). The preview is the database's own drawing of the parts, from the
/// live feeds, a moment after each change; saving hands the recipe to the
/// database, which keeps the board drawn on every screen from then on.
struct DashboardBuilderView: View {
    /// A made board to change; nil makes a new one.
    let editing: Dashboard?
    let onSaved: (UUID) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var template: String?
    @State private var title: String
    @State private var subtitle: String
    @State private var parts: [DashboardPart]
    /// A title the person typed stays when they try another template.
    @State private var named: Bool
    @State private var options = DashboardSourceOptions()
    @State private var preview: [DashboardWidget]
    @State private var previewError: String?
    @State private var drawing = false
    @State private var working = false

    init(editing: Dashboard? = nil, onSaved: @escaping (UUID) -> Void = { _ in }) {
        self.editing = editing
        self.onSaved = onSaved
        let first = DashboardTemplate.all[0]
        _template = State(initialValue: editing == nil ? first.id : editing?.template)
        _title = State(initialValue: editing?.title ?? first.title)
        _subtitle = State(initialValue: editing.map { $0.subtitle ?? "" } ?? first.subtitle ?? "")
        _parts = State(initialValue: editing?.sources ?? first.parts)
        _named = State(initialValue: editing != nil)
        _preview = State(initialValue: editing?.widgets ?? [])
    }

    private var recipe: [DashboardPart] { DashboardPart.normalized(parts) }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !working && !trimmedTitle.isEmpty && !recipe.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if editing == nil { templates }
                Section("Dashboard") {
                    // Typing (not a template) names the board.
                    TextField("Title", text: Binding(get: { title }, set: { title = $0; named = true }))
                    TextField("Subtitle", text: Binding(get: { subtitle }, set: { subtitle = $0; named = true }), prompt: Text("Optional"))
                }
                previewSection
                ForEach($parts) { $part in
                    Section {
                        PartFields(part: $part, options: options)
                    } header: {
                        partHeader(part)
                    } footer: {
                        Text(part.describe(options))
                    }
                }
                Section {
                    Menu {
                        ForEach(DashboardPart.Kind.allCases, id: \.self) { kind in
                            Button {
                                withAnimation { parts.append(DashboardPart(kind)) }
                            } label: {
                                Label(kind.label, systemImage: kind.systemImage)
                            }
                        }
                    } label: {
                        Label("Add a part", systemImage: "plus.circle.fill")
                    }
                    .disabled(parts.count >= DashboardPart.maxParts)
                } footer: {
                    Text("McFly keeps it drawn as the feeds change, on every display.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editing == nil ? "New dashboard" : "Edit dashboard")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(working ? (editing == nil ? "Creating…" : "Saving…") : (editing == nil ? "Create" : "Save")) {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                }
            }
            .task {
                do { options = try await app.admin.dashboardSources() } catch { app.report(error) }
            }
            // Drawn a moment after the recipe settles; a newer recipe cancels an older draw.
            .task(id: recipe) { await draw(recipe) }
        }
        .macOSFrame(width: 560, height: 720)
    }

    // MARK: Sections

    private var templates: some View {
        Section("Start from") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(DashboardTemplate.all) { t in
                    Button { pick(t) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(Color(hex: t.color)).frame(width: 9, height: 9).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                Text(t.summary).font(.caption2).foregroundStyle(Theme.muted).lineLimit(3).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(t.id == template ? Theme.accentSoft : Theme.sunken.opacity(0.5)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.id == template ? Theme.accent : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(t.id == template ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var previewSection: some View {
        Section {
            NavigationLink {
                BoardPreviewScreen(title: trimmedTitle.isEmpty ? "Untitled" : trimmedTitle, subtitle: subtitle, widgets: preview)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.3.group").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("See it as the display draws it").foregroundStyle(Theme.text)
                        Text(previewError ?? previewSummary).font(.caption).foregroundStyle(previewError == nil ? Theme.muted : Theme.danger)
                    }
                    Spacer()
                    if drawing { ProgressView().controlSize(.small) }
                }
            }
            .disabled(preview.isEmpty)
        } header: {
            Text("Preview")
        }
    }

    private var previewSummary: String {
        if recipe.isEmpty { return "Add a part to see it." }
        if preview.isEmpty { return drawing ? "Drawing…" : "Nothing yet." }
        let count = preview.count == 1 ? "1 widget" : "\(preview.count) widgets"
        return "\(count), from the live feeds"
    }

    private func partHeader(_ part: DashboardPart) -> some View {
        let index = parts.firstIndex { $0.id == part.id } ?? 0
        return HStack(spacing: 6) {
            Circle().fill(Color(hex: part.from.color)).frame(width: 8, height: 8)
            Text(part.from.label)
            Spacer()
            Menu {
                Button("Move up", systemImage: "arrow.up") { move(part, by: -1) }.disabled(index == 0)
                Button("Move down", systemImage: "arrow.down") { move(part, by: 1) }.disabled(index == parts.count - 1)
                Button("Remove", systemImage: "trash", role: .destructive) { withAnimation { parts.removeAll { $0.id == part.id } } }
            } label: {
                Image(systemName: "ellipsis.circle").imageScale(.large)
            }
            .fixedSize()
            .accessibilityLabel("\(part.from.label) options")
        }
    }

    // MARK: Actions

    private func pick(_ t: DashboardTemplate) {
        template = t.id
        withAnimation { parts = t.parts }
        if !named {
            title = t.title
            subtitle = t.subtitle ?? ""
        }
    }

    private func move(_ part: DashboardPart, by step: Int) {
        guard let at = parts.firstIndex(where: { $0.id == part.id }), parts.indices.contains(at + step) else { return }
        withAnimation { parts.swapAt(at, at + step) }
    }

    private func draw(_ recipe: [DashboardPart]) async {
        guard !recipe.isEmpty else {
            preview = []
            previewError = nil
            return
        }
        drawing = true
        defer { drawing = false }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
            let widgets = try await app.admin.previewDashboard(recipe)
            guard !Task.isCancelled else { return }
            preview = widgets
            previewError = nil
        } catch {
            guard !Task.isCancelled else { return }
            previewError = McFlyError.describe(error)
        }
    }

    private func save() async {
        working = true
        defer { working = false }
        do {
            let subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = try await app.admin.saveDashboard(id: editing?.id, title: trimmedTitle, subtitle: subtitle.isEmpty ? nil : subtitle,
                                                       template: template, parts: recipe)
            await app.feeds.refresh()
            dismiss()
            onSaved(id)
        } catch {
            app.report(error)
        }
    }
}

// MARK: One part

/// Where one part pulls from, its kind's own choices.
private struct PartFields: View {
    @Binding var part: DashboardPart
    let options: DashboardSourceOptions

    var body: some View {
        switch part.from {
        case .quotes:
            NameChips(picked: $part.symbols,
                      choices: options.symbols.map { .init(value: $0.symbol, label: $0.symbol, hidden: $0.hidden == true) },
                      none: "None picked: every symbol on the display, in its order.",
                      empty: "No symbols yet: a markets agent's first push adds them.")
            showPicker([.tiles, .chart])
            limit
        case .metrics:
            NameChips(picked: $part.keys,
                      choices: options.metrics.map { .init(value: $0.key, label: $0.label, hidden: $0.hidden == true) },
                      none: part.group.map { "None picked: every \($0) metric." } ?? "None picked: every metric on the display.",
                      empty: "No metrics yet: an agent's first push to /ingest/metrics adds them.")
            let groups = Array(Set(options.metrics.compactMap(\.group))).sorted()
            if part.keys.isEmpty, !groups.isEmpty {
                Picker("Group", selection: $part.group) {
                    Text("Any group").tag(String?.none)
                    ForEach(groups, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            showPicker([.tiles, .chart])
            limit
        case .projects:
            NameChips(picked: $part.projects,
                      choices: options.projects.map { .init(value: $0.id, label: $0.name, hidden: false) },
                      none: "None picked: the active and blocked ones.",
                      empty: "No projects yet: an agent's first push to /ingest/projects adds them.")
            showPicker([.progress, .list])
            limit
            if part.show == .list { titleField("Projects") }
        case .calendar:
            NameChips(picked: $part.calendars,
                      choices: options.calendars.map { .init(value: $0, label: $0, hidden: false) },
                      none: "None picked: every calendar.",
                      empty: "No calendars yet: add one in the console's Calendars, or have an agent push events.")
            Picker("How far ahead", selection: $part.days) {
                ForEach(DashboardPart.calendarDays, id: \.self) { d in
                    Text(d == 1 ? "Today" : d == 2 ? "Today and tomorrow" : d == 7 ? "A week" : d == 14 ? "Two weeks" : d == 31 ? "A month" : "\(d) days").tag(d)
                }
            }
            limit
            titleField(part.days == 1 ? "Today" : part.days == 2 ? "Today and tomorrow" : "Next \(part.days) days")
        case .todos:
            Picker("Which", selection: $part.todos) {
                Text("Both").tag(DashboardPart.Todos.all)
                Text("Todos").tag(DashboardPart.Todos.todo)
                Text("Reminders").tag(DashboardPart.Todos.reminder)
            }
            .pickerStyle(.segmented)
            limit
            titleField(part.todos == .reminder ? "Reminders" : "To do")
        case .news:
            Picker("Section", selection: $part.section) {
                Text("The top headlines").tag(String?.none)
                ForEach(options.newsSections, id: \.key) { Text($0.name).tag(String?.some($0.key)) }
            }
            limit
            titleField("Headlines")
        case .brief:
            Picker("Kind", selection: $part.briefKind) {
                Text("Any kind").tag(Brief.Kind?.none)
                ForEach(Brief.Kind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(Brief.Kind?.some($0)) }
            }
            Picker("From", selection: $part.agent) {
                Text("Any agent").tag(String?.none)
                ForEach(options.agents, id: \.id) { Text($0.name).tag(String?.some($0.id)) }
            }
            titleField("The brief's own title")
        case .agents:
            NameChips(picked: $part.agents,
                      choices: options.agents.map { .init(value: $0.id, label: $0.name, hidden: $0.hasKey == false) },
                      none: "None picked: every agent with a key.",
                      empty: "No agents yet.")
            Picker("Quiet after", selection: $part.hours) {
                ForEach(DashboardPart.agentHours, id: \.self) { Text(DashboardPart.hoursLabel($0).capitalizedFirst).tag($0) }
            }
        case .note:
            titleField("Optional")
            TextField("Words", text: $part.body, prompt: Text("Deploy window tonight, 9 to 10 PM."), axis: .vertical)
                .lineLimit(3...8)
            if part.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("A note with no words is left off the board.").font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    private func showPicker(_ choices: [DashboardPart.Show]) -> some View {
        Picker("Show", selection: $part.show) {
            ForEach(choices, id: \.self) { show in
                Text(show == .tiles ? "Tiles" : show == .chart ? "Charts" : show == .progress ? "Progress" : "A list").tag(show)
            }
        }
        .pickerStyle(.segmented)
    }

    private var limit: some View {
        Stepper(value: Binding(get: { part.limit ?? part.defaultLimit }, set: { part.limit = $0 }), in: 1...part.maxLimit) {
            HStack {
                Text("At most")
                Spacer()
                Text("\(part.limit ?? part.defaultLimit)").monospacedDigit().foregroundStyle(Theme.muted)
            }
        }
    }

    private func titleField(_ placeholder: String) -> some View {
        TextField("Title", text: Binding(get: { part.title ?? "" }, set: { part.title = $0.isEmpty ? nil : $0 }), prompt: Text(placeholder))
    }
}

/// Toggles for a list of names, kept in the order they're picked (a number
/// shows it once there are two). A name picked earlier that no longer comes
/// up (a symbol since deleted) stays, so it can be taken off.
private struct NameChips: View {
    struct Choice: Hashable {
        var value: String
        var label: String
        /// Hidden on the display, or an agent without a key: dimmed.
        var hidden: Bool
    }

    @Binding var picked: [String]
    let choices: [Choice]
    let none: String
    let empty: String

    var body: some View {
        let known = Set(choices.map(\.value))
        let all = choices + picked.filter { !known.contains($0) }.map { Choice(value: $0, label: $0, hidden: true) }
        VStack(alignment: .leading, spacing: 8) {
            if all.isEmpty {
                Text(empty).font(.caption).foregroundStyle(Theme.muted)
            } else {
                ChipFlow(spacing: 6) {
                    ForEach(all, id: \.value) { choice in
                        let order = picked.firstIndex(of: choice.value)
                        Button {
                            if let order { picked.remove(at: order) } else { picked.append(choice.value) }
                        } label: {
                            HStack(spacing: 4) {
                                Text(choice.label).lineLimit(1)
                                if let order, picked.count > 1 {
                                    Text("\(order + 1)").font(.caption2.weight(.bold)).monospacedDigit().opacity(0.7)
                                }
                            }
                            .font(.subheadline.weight(order == nil ? .regular : .semibold))
                            .foregroundStyle(order == nil ? (choice.hidden ? Theme.muted : Theme.text) : Theme.accentInk)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(order == nil ? Theme.sunken.opacity(0.7) : Theme.accent))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(order == nil ? [] : .isSelected)
                    }
                }
                Text(picked.isEmpty ? none : "In the order you picked them.").font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: Preview

/// The recipe as the display will draw it: the board's own bento.
private struct BoardPreviewScreen: View {
    let title: String
    let subtitle: String
    let widgets: [DashboardWidget]
    @State private var width: CGFloat = 0

    private static let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000b1")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                    if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(Theme.muted) }
                }
                if width > 0 {
                    BoardGrid(dashboard: Dashboard(id: Self.id, agentId: Self.id, key: "preview", title: title, widgets: widgets),
                              columns: DashboardsView.columns(for: width), width: width) { _ in }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .padding(Theme.page)
        }
        .screenBackground()
        .navigationTitle("Preview")
        .inlineTitle()
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
