import SwiftUI

/// Email + password, or an emailed link. The first account on a fresh project
/// becomes the admin; anyone else is told so after signing in (NotAdminView).
struct SignInView: View {
    @Environment(AppModel.self) private var app

    private enum Field { case email, password }

    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @FocusState private var focus: Field?

    private var hasEmail: Bool { email.contains("@") && email.contains(".") }
    private var canSubmit: Bool { hasEmail && !password.isEmpty && !working }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                hero
                if let sentTo = app.magicLinkSentTo {
                    sent(to: sentTo)
                } else {
                    form
                }
                if !app.isDemo, !Config.isConfigured {
                    Text(Config.unconfiguredMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Theme.page)
            .padding(.top, 60)
            .padding(.bottom, 24)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .macOSFrame(width: 560, height: 640)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            FluxMark()
                .frame(width: 72, height: 72)
                .padding(.bottom, 6)
            Wordmark(size: 44)
                .foregroundStyle(Theme.text)
            Text("Your agents' display, on your phone and your Mac.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
        .background(alignment: .top) {
            GlowView().frame(height: 260).offset(y: -110)
        }
        .accessibilityElement(children: .combine)
    }

    private var form: some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                fieldRow(icon: "envelope.fill") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .emailField()
                        .submitLabel(.next)
                        .focused($focus, equals: .email)
                        .onSubmit { focus = .password }
                }
                Divider().padding(.leading, 52)
                fieldRow(icon: "lock.fill") {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focus, equals: .password)
                        .onSubmit { if canSubmit { Task { await signIn() } } }
                }
            }
            .textFieldStyle(.plain)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))

            Button {
                Task { await signIn() }
            } label: {
                Group {
                    if working { ProgressView().tint(.white) } else { Text("Sign in") }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.pill())
            .disabled(!canSubmit)

            Button {
                Task { await sendLink() }
            } label: {
                Text("Email me a link")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.pill(.soft))
            .disabled(!hasEmail || working)
        }
        .padding(16)
        .card(padding: 0)
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func sent(to address: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "paperplane.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
            Text("Check your email")
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text("A sign-in link is on its way to \(address). Open it on this device to finish.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
            Button("Use a different email") { app.magicLinkSentTo = nil }
                .buttonStyle(.pill(.neutral))
        }
        .card(padding: 24)
    }

    private func fieldRow<Content: View>(icon: String, @ViewBuilder field: () -> Content) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            field().foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private func signIn() async {
        working = true
        defer { working = false }
        focus = nil
        await app.signIn(email: email, password: password)
    }

    private func sendLink() async {
        working = true
        defer { working = false }
        focus = nil
        _ = await app.sendMagicLink(email: email)
    }
}

/// Signed in with an account that isn't McFly's admin.
struct NotAdminView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: 44))
                .foregroundStyle(Theme.muted)
            Text("This account isn't a McFly admin.")
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text("The first account to sign up becomes the admin. An admin can add others from the console.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
            if let email = app.email {
                Text(email).font(.footnote.monospaced()).foregroundStyle(Theme.muted)
            }
            Button("Check again") { Task { await app.checkAdmin() } }
                .buttonStyle(.pill(.soft))
            Button("Sign out") { Task { await app.signOut() } }
                .buttonStyle(.pill())
        }
        .padding(32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}
