import McFlyKit
import SwiftUI

/// Paired displays: online within 15 minutes, rename, revoke, and pair a new one.
struct DisplaysView: View {
    @Environment(AppModel.self) private var app
    @State private var devices: [Device] = []
    @State private var loaded = false
    @State private var showPair = false
    @State private var renaming: Device?
    @State private var newName = ""
    @State private var revoking: Device?

    var body: some View {
        List {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if devices.isEmpty {
                EmptyCard(text: "No displays paired yet. Tap + and enter the code on the screen.", systemImage: "tv")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            ForEach(devices) { device in
                DeviceRow(device: device)
                    .contextMenu {
                        Button("Rename…") { startRename(device) }
                        Button("Revoke…", role: .destructive) { revoking = device }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Revoke", role: .destructive) { revoking = device }
                        Button("Rename") { startRename(device) }.tint(Theme.accent)
                    }
            }
        }
        .groupedList()
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Displays")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showPair = true } label: { Label("Pair a display", systemImage: "plus") }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: app.pendingPairCode) { _, code in
            if code != nil { showPair = true }
        }
        .onAppear {
            if app.pendingPairCode != nil { showPair = true }
        }
        .sheet(isPresented: $showPair, onDismiss: {
            app.pendingPairCode = nil
            Task { await load() }
        }) {
            PairDisplayView(initialCode: app.pendingPairCode ?? "")
                .environment(app)
        }
        .alert("Rename display", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let device = renaming { Task { await rename(device, to: newName) } }
                renaming = nil
            }
        }
        .confirmationDialog("Revoke this display?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
                            titleVisibility: .visible) {
            Button("Revoke \(revoking?.name ?? "display")", role: .destructive) {
                if let device = revoking { Task { await revoke(device) } }
                revoking = nil
            }
            Button("Cancel", role: .cancel) { revoking = nil }
        } message: {
            Text("It signs out at once and shows a new pairing code. Pair it again any time.")
        }
    }

    private func load() async {
        do {
            devices = try await app.admin.listDevices()
        } catch {
            app.report(error)
        }
        loaded = true
    }

    private func startRename(_ device: Device) {
        newName = device.name
        renaming = device
    }

    private func rename(_ device: Device, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != device.name else { return }
        do {
            try await app.admin.renameDevice(device.id, name: trimmed)
            await load()
        } catch {
            app.report(error)
        }
    }

    private func revoke(_ device: Device) async {
        do {
            try await app.admin.revokeDevice(device.id)
            await load()
        } catch {
            app.report(error)
        }
    }
}

struct DeviceRow: View {
    let device: Device

    var body: some View {
        TimelineView(.everyMinute) { context in
            let online = device.isOnline(at: context.date)
            HStack(spacing: 12) {
                Image(systemName: "tv")
                    .font(.title3)
                    .foregroundStyle(online ? Theme.accent : Theme.muted)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name).font(.headline).foregroundStyle(Theme.text)
                    Text(Format.lastSeen(device, now: context.date))
                        .font(.caption)
                        .foregroundStyle(online ? Theme.up : Theme.muted)
                }
                Spacer()
                Circle()
                    .fill(online ? Theme.up : Theme.divider)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel(online ? "Online" : "Offline")
            }
            .padding(.vertical, 4)
        }
    }
}

/// Enter (or scan) the 6-digit code on the display, name it, claim it.
struct PairDisplayView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    enum Step: Equatable { case entering, claiming, paired(UUID) }

    @State private var code: String
    @State private var name = ""
    @State private var step: Step = .entering
    @State private var message: String?
    @State private var scanning = false
    @FocusState private var codeFocused: Bool

    init(initialCode: String = "") {
        _code = State(initialValue: PairingCode.normalize(initialCode))
    }

    private var canPair: Bool { PairingCode.isValid(code) && step == .entering }

    var body: some View {
        NavigationStack {
            Group {
                if case .paired = step {
                    success
                } else {
                    form
                }
            }
            .screenBackground()
            .navigationTitle("Pair a display")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .entering ? "Cancel" : "Done") { dismiss() }
                        .disabled(step == .claiming)
                }
            }
        }
        .macOSFrame(width: 460, height: 520)
        #if os(iOS)
        .sheet(isPresented: $scanning) {
            QRScannerSheet { scanned in
                scanning = false
                if let found = PairingCode.code(fromScanned: scanned) {
                    code = found
                    message = nil
                } else {
                    message = "That QR code isn't a McFly pairing code."
                }
            }
        }
        #endif
        .onAppear { codeFocused = code.isEmpty }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "tv.and.mediabox")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.accent)
                    Text("The display shows a 6-digit code (and a QR code) until it's paired. Codes last 10 minutes.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 6) {
                    Text("CODE").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                    TextField("123456", text: $code)
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .digitsField()
                        .focused($codeFocused)
                        .onChange(of: code) { _, new in
                            let tidy = PairingCode.normalize(new)
                            if tidy != new { code = tidy }
                        }
                        .padding(.vertical, 12)
                        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                        .accessibilityLabel("Pairing code")
                    Text("NAME (OPTIONAL)").font(.caption.weight(.bold)).foregroundStyle(Theme.muted).padding(.top, 8)
                    TextField("Kitchen", text: $name)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                }
                .card()

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Theme.down)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await claim() }
                } label: {
                    Group {
                        if step == .claiming { ProgressView().tint(.white) } else { Text("Pair") }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.pill())
                .disabled(!canPair)

                #if os(iOS)
                Button {
                    scanning = true
                } label: {
                    Label("Scan the QR code", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.pill(.soft))
                .disabled(step == .claiming)
                #endif
            }
            .padding(Theme.page)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
    }

    private var success: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.up)
            Text("Paired")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.text)
            Text("\(name.isEmpty ? "The display" : name) is signing in now and will show your feeds in a moment.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
            Button("Done") { dismiss() }
                .buttonStyle(.pill())
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func claim() async {
        step = .claiming
        message = nil
        do {
            let id = try await app.pairDisplay(code: code, name: name)
            step = .paired(id)
        } catch {
            message = McFlyError.describe(error)
            step = .entering
        }
    }
}
