import McFlyKit
import SwiftUI

@main
struct McFlyApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .followsAppearance()
                .task { await app.start() }
                // mcfly://auth-callback, mcfly://pair?code=… and the https://mcfly.bot/pair universal link.
                .onOpenURL { app.handleOpenURL($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { app.handleOpenURL(url) }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif
    }
}

/// Routes between loading, sign-in, "not an admin" and the app.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            switch app.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .screenBackground()
            case .unreachable:
                UnreachableView()
            case .signedOut:
                SignInView()
            case .notAdmin:
                NotAdminView()
            case .ready:
                MainView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: app.phase)
        .showsAppErrors()
    }
}

/// A saved account that couldn't be checked: retry, or sign out.
private struct UnreachableView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(Theme.muted)
            Text(app.errorMessage ?? "McFly couldn't be reached.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
            Button("Try again") {
                app.errorMessage = nil
                Task { await app.checkAdmin() }
            }
            .buttonStyle(.pill())
            Button("Sign out") { Task { await app.signOut() } }
                .buttonStyle(.pill(.neutral))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}

/// The screens, in sidebar order on the Mac and tab order on the iPhone.
enum Screen: String, CaseIterable, Identifiable, Hashable {
    case home, briefs, markets, news, voice, projects, dashboards, calendar, displays, agents, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home: return "Home"
        case .briefs: return "Briefs"
        case .markets: return "Markets"
        case .news: return "News"
        case .voice: return "Voice"
        case .projects: return "Projects"
        case .dashboards: return "Dashboards"
        case .calendar: return "Calendar"
        case .displays: return "Displays"
        case .agents: return "Agents"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .briefs: return "text.alignleft"
        case .markets: return "chart.line.uptrend.xyaxis"
        case .news: return "newspaper.fill"
        case .voice: return "waveform"
        case .projects: return "folder.fill"
        case .dashboards: return "rectangle.3.group.fill"
        case .calendar: return "calendar"
        case .displays: return "tv"
        case .agents: return "cpu"
        case .settings: return "gearshape.fill"
        }
    }

    /// The iPhone's tabs, the display's first four; the rest sit behind More,
    /// which makes five, as many as an iPhone's tab bar shows. Voice is also
    /// Home's Ask bar.
    static let tabs: [Screen] = [.home, .briefs, .markets, .news]
    static let more: [Screen] = [.projects, .dashboards, .calendar, .voice, .displays, .agents, .settings]
    /// The Mac sidebar's groups.
    static let feedScreens: [Screen] = [.home, .briefs, .markets, .news, .projects, .dashboards, .calendar, .voice]
    static let manageScreens: [Screen] = [.displays, .agents, .settings]

    @ViewBuilder
    var view: some View {
        switch self {
        case .home: HomeView()
        case .briefs: BriefsView()
        case .markets: MarketsView()
        case .news: NewsView()
        case .voice: VoiceHubView()
        case .projects: ProjectsView()
        case .dashboards: DashboardsView()
        case .calendar: CalendarView()
        case .displays: DisplaysView()
        case .agents: AgentsView()
        case .settings: SettingsView()
        }
    }
}

/// A TabView on the iPhone, a sidebar on the Mac. A pairing link opens the
/// Displays screen on either.
struct MainView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Screen = .home

    var body: some View {
        Group {
            #if os(iOS)
            phone
            #else
            desktop
            #endif
        }
        .onChange(of: app.pendingPairCode) { _, code in
            if code != nil { selection = .displays }
        }
        // Back in front after a while: what the agents pushed meanwhile. The
        // display syncs every minute; the phone catches up when it's looked at.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let loaded = app.feeds.loadedAt, Date.now.timeIntervalSince(loaded) > 60 else { return }
            Task { await app.feeds.refresh() }
        }
    }

    #if os(iOS)
    private var phone: some View {
        TabView(selection: Binding(
            get: { Screen.tabs.contains(selection) ? selection : .projects },
            set: { selection = $0 }
        )) {
            ForEach(Screen.tabs) { screen in
                NavigationStack { screen.view }
                    .tabItem { Label(screen.title, systemImage: screen.icon) }
                    .tag(screen)
            }
            NavigationStack {
                MoreView(selection: $selection)
            }
            .tabItem { Label("More", systemImage: "ellipsis.circle") }
            .tag(Screen.projects)
        }
    }
    #else
    private var desktop: some View {
        NavigationSplitView {
            List(selection: Binding(get: { Optional(selection) }, set: { selection = $0 ?? .home })) {
                Section("Feeds") {
                    ForEach(Screen.feedScreens) { screen in
                        Label(screen.title, systemImage: screen.icon).tag(screen)
                    }
                }
                Section("Manage") {
                    ForEach(Screen.manageScreens) { screen in
                        Label(screen.title, systemImage: screen.icon).tag(screen)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .navigationTitle(app.feeds.displayName)
        } detail: {
            NavigationStack { selection.view }
        }
    }
    #endif
}

#if os(iOS)
/// The iPhone's More tab: the management screens.
struct MoreView: View {
    @Binding var selection: Screen
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            Section("Feeds") {
                ForEach(Screen.more.filter { !Screen.manageScreens.contains($0) }) { screen in
                    NavigationLink(value: screen) { Label(screen.title, systemImage: screen.icon) }
                }
            }
            Section("Manage") {
                ForEach(Screen.manageScreens) { screen in
                    NavigationLink(value: screen) { Label(screen.title, systemImage: screen.icon) }
                }
            }
        }
        .navigationTitle("More")
        .navigationDestination(for: Screen.self) { $0.view }
        .groupedList()
        // A pairing link lands on Displays even from another tab.
        .navigationDestination(isPresented: Binding(
            get: { app.pendingPairCode != nil && selection == .displays },
            set: { if !$0 { selection = .projects } }
        )) { DisplaysView() }
    }
}
#endif
