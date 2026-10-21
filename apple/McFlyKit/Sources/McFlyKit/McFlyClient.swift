import Foundation
import Supabase

/// The signed-in state as the app sees it.
public enum SessionState: Equatable, Sendable {
    case signedIn
    case signedOut
    /// A saved session that couldn't be refreshed because the network is down:
    /// still an account, so show "try again", not the sign-in screen.
    case unreachable
}

/// One Supabase client and the McFly services built on it. The anon key is
/// made to ship in apps; row-level security does the protecting.
public final class McFlyClient: Sendable {
    public let supabase: SupabaseClient
    public let feeds: SupabaseFeedSource
    public let admin: SupabaseAdminService
    public let pairing: PairingClient
    public let assistant: AssistantClient
    public let articles: ArticleClient
    public let authCallbackURL: URL

    public init(supabaseURL: URL, anonKey: String, authCallbackURL: URL) {
        let supabase = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(auth: .init(storage: AuthClient.Configuration.defaultLocalStorage,
                                                        redirectToURL: authCallbackURL, flowType: .pkce)))
        self.supabase = supabase
        self.authCallbackURL = authCallbackURL
        feeds = SupabaseFeedSource(client: supabase)
        admin = SupabaseAdminService(client: supabase)
        pairing = PairingClient(functions: supabase.functions)
        articles = ArticleClient(functions: supabase.functions)
        assistant = AssistantClient(supabaseURL: supabaseURL, anonKey: anonKey) {
            // Refreshed if it expired; throws when nobody is signed in.
            try await supabase.auth.session.accessToken
        }
    }

    // MARK: Auth

    public var currentEmail: String? { supabase.auth.currentUser?.email }
    public var isSignedIn: Bool { supabase.auth.currentSession != nil }

    public func signIn(email: String, password: String) async throws {
        _ = try await supabase.auth.signIn(email: email, password: password)
    }

    /// Emails a sign-in link that opens the app at `authCallbackURL`. A new
    /// address gets an account: on a fresh project that first account is the
    /// admin (handle_new_user).
    public func sendMagicLink(email: String) async throws {
        try await supabase.auth.signInWithOTP(email: email, redirectTo: authCallbackURL)
    }

    public func signOut() async {
        try? await supabase.auth.signOut()
    }

    /// Finishes an email link: a PKCE `code` from a magic link, or tokens in
    /// the fragment from an invite sent by the console.
    public func handleAuthCallback(_ url: URL) async throws {
        var fragment = URLComponents()
        fragment.percentEncodedQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment
        let items = fragment.queryItems ?? []
        let value: (String) -> String? = { name in items.first { $0.name == name }?.value }
        if let problem = value("error_description") ?? value("error") {
            throw McFlyError.message(problem.replacingOccurrences(of: "+", with: " ").sentenceCased)
        }
        if let accessToken = value("access_token"), let refreshToken = value("refresh_token") {
            _ = try await supabase.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
        } else {
            _ = try await supabase.auth.session(from: url)
        }
    }

    public func isAuthCallback(_ url: URL) -> Bool {
        url.scheme?.lowercased() == authCallbackURL.scheme?.lowercased()
            && url.host?.lowercased() == authCallbackURL.host?.lowercased()
    }

    /// Signed in / out, as it changes. The first value is the saved session's state.
    public var sessionStates: AsyncStream<SessionState> {
        AsyncStream { continuation in
            let task = Task {
                for await (event, session) in supabase.auth.authStateChanges {
                    guard [.initialSession, .signedIn, .signedOut].contains(event) else { continue }
                    if session != nil {
                        continuation.yield(.signedIn)
                    } else if event == .initialSession, supabase.auth.currentSession != nil {
                        // The saved session couldn't be refreshed. Offline, that's
                        // still a signed-in account; a refusal means signed out.
                        do {
                            _ = try await supabase.auth.session
                            continuation.yield(.signedIn)
                        } catch is URLError {
                            continuation.yield(.unreachable)
                        } catch {
                            continuation.yield(.signedOut)
                        }
                    } else {
                        continuation.yield(.signedOut)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
