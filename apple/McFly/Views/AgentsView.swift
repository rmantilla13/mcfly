import McFlyKit
import SwiftUI

/// The agents that push, their last push, and keys: make one, rotate, revoke, delete.
struct AgentsView: View {
    @Environment(AppModel.self) private var app
    @State private var agents: [Agent] = []
    @State private var loaded = false
    @State private var showNew = false
    @State private var revealed: RevealedKey?
    @State private var confirming: PendingAction?

    struct RevealedKey: Identifiable {
        let id = UUID()
        let title: String
        let key: String
    }

    enum PendingAction: Identifiable {
        case rotate(Agent), revoke(Agent), delete(Agent)

        var id: UUID {
            switch self {
            case .rotate(let a), .revoke(let a), .delete(let a): return a.id
            }
        }
    }

    var body: some View {
        List {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if agents.isEmpty {
                EmptyCard(text: "No agents yet. Make one to get a key it can push with.", systemImage: "cpu")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            ForEach(agents) { agent in
                AgentRow(agent: agent)
                    .contextMenu { actions(agent) }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) { confirming = .delete(agent) }
                        if !agent.isRevoked {
                            Button("Revoke") { confirming = .revoke(agent) }.tint(Theme.amber)
                        }
                    }
            }
        }
        .groupedList()
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Agents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: { Label("New agent", systemImage: "plus") }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showNew, onDismiss: { Task { await load() } }) {
            NewAgentView { created in
                revealed = RevealedKey(title: "\(created.slug)'s key", key: created.key)
            }
            .environment(app)
        }
        .sheet(item: $revealed) { reveal in
            KeyRevealView(title: reveal.title, key: reveal.key) { revealed = nil }
                .macOSFrame(width: 480, height: 300)
                .presentationDetents([.medium])
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { action in
            switch action {
            case .rotate(let agent):
                Button("Rotate key") { Task { await rotate(agent) } }
            case .revoke(let agent):
                Button("Revoke \(agent.name)", role: .destructive) { Task { await revoke(agent) } }
            case .delete(let agent):
                Button("Delete \(agent.name)", role: .destructive) { Task { await delete(agent) } }
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: { action in
            switch action {
            case .rotate: Text("The old key stops working at once. The new one is shown once.")
            case .revoke: Text("Its key is removed and its pushes refused. What it pushed stays. Rotating the key brings it back.")
            case .delete: Text("The agent and everything it pushed are removed.")
            }
        }
    }

    private var confirmTitle: String {
        switch confirming {
        case .rotate: return "Rotate this agent's key?"
        case .revoke: return "Revoke this agent?"
        case .delete: return "Delete this agent?"
        case nil: return ""
        }
    }

    @ViewBuilder
    private func actions(_ agent: Agent) -> some View {
        Button(agent.isRevoked ? "New key (un-revoke)…" : "Rotate key…") { confirming = .rotate(agent) }
        if !agent.isRevoked {
            Button("Revoke…") { confirming = .revoke(agent) }
        }
        Button("Delete…", role: .destructive) { confirming = .delete(agent) }
    }

    private func load() async {
        do {
            agents = try await app.admin.listAgents()
        } catch {
            app.report(error)
        }
        loaded = true
    }

    private func rotate(_ agent: Agent) async {
        do {
            let key = try await app.admin.rotateAgentKey(agent.id)
            revealed = RevealedKey(title: "\(agent.name)'s new key", key: key)
            await load()
        } catch {
            app.report(error)
        }
    }

    private func revoke(_ agent: Agent) async {
        do {
            try await app.admin.revokeAgent(agent.id)
            await load()
        } catch {
            app.report(error)
        }
    }

    private func delete(_ agent: Agent) async {
        do {
            try await app.admin.deleteAgent(agent.id)
            await load()
        } catch {
            app.report(error)
        }
    }
}

struct AgentRow: View {
    let agent: Agent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: agent.kind.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color(hex: agent.color), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(agent.isRevoked ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(agent.name).font(.headline).foregroundStyle(Theme.text)
                    if agent.isRevoked { Tag(text: "Revoked", color: Theme.down) }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(agent.lastError == nil ? Theme.muted : Theme.down)
                    .lineLimit(2)
            }
            Spacer()
            if let prefix = agent.keyPrefix {
                Text(prefix + "…")
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        var parts = [agent.kind.label]
        if let seen = agent.lastSeenAt {
            parts.append("pushed \(Format.relative(seen).lowercased())")
        } else {
            parts.append("never pushed")
        }
        if let pushes = agent.pushes7d, pushes > 0 { parts.append("\(pushes) in 7 days") }
        if let error = agent.lastError { parts.append("last error: \(error)") }
        return parts.joined(separator: " · ")
    }
}

/// Name, kind and color; the key comes back once, to the caller.
struct NewAgentView: View {
    let onCreated: (CreatedAgent) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: Agent.Kind = .other
    @State private var color = agentPalette[3]
    @State private var working = false
    @FocusState private var nameFocused: Bool

    private var canCreate: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !working }

    var body: some View {
        NavigationStack {
            Form {
                Section("Agent") {
                    TextField("Name", text: $name).focused($nameFocused)
                    Picker("Kind", selection: $kind) {
                        ForEach(Agent.Kind.allCases, id: \.self) { kind in
                            Label(kind.label, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                }
                Section("Color") {
                    HStack(spacing: 12) {
                        ForEach(agentPalette, id: \.self) { hex in
                            Button {
                                color = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(Theme.text, lineWidth: color == hex ? 3 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(hex)
                            .accessibilityAddTraits(color == hex ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Text("The kind is a label for icons and colors; any agent may push to any feed. The key is shown once after creating.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New agent")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(working ? "Creating…" : "Create") { Task { await create() } }
                        .disabled(!canCreate)
                }
            }
        }
        .macOSFrame(width: 460, height: 420)
        .onAppear { nameFocused = true }
    }

    private func create() async {
        working = true
        defer { working = false }
        do {
            let created = try await app.admin.createAgent(name: name.trimmingCharacters(in: .whitespaces), kind: kind, color: color)
            dismiss()
            onCreated(created)
        } catch {
            app.report(error)
        }
    }
}
