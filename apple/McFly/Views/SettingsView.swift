import McFlyKit
import SwiftUI

/// The account, the platform settings the app can change, and the version.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var settings: PlatformSettings?
    @State private var displayName = ""
    @State private var timezone = ""
    @State private var provider: AssistantProvider = .claude
    @State private var saving = false
    @State private var saved = false
    @State private var locating = false
    @State private var locationNote: LocationNote?
    @State private var sample = VoiceSpeaker()

    private var changed: Bool {
        guard let settings else { return false }
        return displayName.trimmingCharacters(in: .whitespaces) != settings.displayName || timezone != settings.timezone
            || provider != settings.assistantProvider
    }

    private var timezoneKnown: Bool { timezone.isEmpty || TimeZone(identifier: timezone) != nil }

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Email", value: app.email ?? "—")
                if app.isDemo {
                    Text("Demo mode: the seed's data, no backend.").font(.footnote).foregroundStyle(Theme.muted)
                }
                Button("Sign out", role: .destructive) { Task { await app.signOut() } }
                    .disabled(app.isDemo)
            }
            Section {
                TextField("Display name", text: $displayName)
                TextField("Timezone", text: $timezone)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                if !timezoneKnown {
                    Text("Not a known timezone. Use an identifier like America/Chicago.")
                        .font(.footnote).foregroundStyle(Theme.down)
                }
                Button {
                    Task { await useLocation() }
                } label: {
                    HStack {
                        Label(locating ? "Finding where you are…" : "Use my location", systemImage: "location.fill")
                        if locating {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(locating || saving)
                if let locationNote {
                    Text(locationNote.text)
                        .font(.footnote).foregroundStyle(locationNote.isProblem ? Theme.down : Theme.muted)
                }
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text(saving ? "Saving…" : "Save")
                        if saved { Image(systemName: "checkmark").foregroundStyle(Theme.up) }
                    }
                }
                .disabled(!changed || saving || !timezoneKnown || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Display")
            } footer: {
                if let settings {
                    Text("Briefs are kept \(settings.briefsKeepDays) days, quote and metric history \(settings.quotesKeepDays) and \(settings.metricsKeepDays) days, events \(settings.eventsKeepDays) days, and the newest \(settings.newsKeepReports) reports. Change those in the console.")
                }
            }
            Section {
                Picker("Answers from", selection: $provider) {
                    ForEach(AssistantProvider.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Assistant")
            } footer: {
                Text("Which model answers Voice and Ask, here and on the display. Saved with the display settings above.")
            }
            Section {
                Picker("Voice", selection: Binding(get: { app.voice }, set: { app.chooseVoice($0) })) {
                    ForEach(VoiceChoice.allCases) { Text($0.name).tag($0) }
                }
                Button(sample.isSpeaking ? "Stop" : "Hear it") {
                    if sample.isSpeaking {
                        sample.stop()
                    } else {
                        sample.speak("Hi, I'm McFly. This is how I'll read your answers.")
                    }
                }
            } header: {
                Text("Voice")
            } footer: {
                Text(BuiltInVoice.isBundled
                     ? "Heart, Bella, Michael or Fenrir is McFly's voice everywhere: picked here, the display and the web speak with it too, and a pick there reaches this device. This device's voice stays on this device. The first answer after an update takes a moment longer while the voice gets ready."
                     : "This build doesn't include McFly's voices, so this device's voice reads answers. Picking one of McFly's still sets it for the display and the web.")
            }
            .onChange(of: app.voice) { _, _ in
                sample.stop()
                sample.prepare()
            }
            Section("About") {
                LabeledContent("Version", value: Config.appVersion)
                LabeledContent("Speech", value: VoiceListener.engineDescription)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Settings")
        .task { await load() }
        .task { await app.syncVoice() }
    }

    private func load() async {
        do {
            let current = try await app.admin.settings()
            settings = current
            displayName = current.displayName
            timezone = current.timezone
            provider = current.assistantProvider
        } catch {
            app.report(error)
        }
    }

    /// Fills the timezone from where this device is (LocationTimeZone); Save still writes it.
    private func useLocation() async {
        locating = true
        locationNote = nil
        defer { locating = false }
        do {
            let zone = try await LocationTimeZone().current()
            timezone = zone.identifier
            locationNote = LocationNote(text: "From your location.", isProblem: false)
        } catch {
            locationNote = LocationNote(text: error.localizedDescription, isProblem: true)
        }
    }

    private func save() async {
        saving = true
        saved = false
        defer { saving = false }
        do {
            let updated = try await app.admin.updateSettings(
                displayName: displayName.trimmingCharacters(in: .whitespaces),
                timezone: timezone.isEmpty ? nil : timezone,
                assistantProvider: provider)
            settings = updated
            displayName = updated.displayName
            timezone = updated.timezone
            provider = updated.assistantProvider
            saved = true
            await app.feeds.refresh()
        } catch {
            app.report(error)
        }
    }
}

private struct LocationNote: Equatable {
    var text: String
    var isProblem: Bool
}
