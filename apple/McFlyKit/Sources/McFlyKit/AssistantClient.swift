import Foundation

/// One server-sent event from the `assistant` function (PLATFORM_SPEC §2.4).
public enum AssistantEvent: Equatable, Sendable {
    case delta(String)
    case done(AssistantReply)
    case error(String)

    /// `done` and `error` end the stream.
    public var isFinal: Bool {
        switch self {
        case .done, .error: return true
        case .delta: return false
        }
    }
}

public struct AssistantReply: Codable, Equatable, Sendable {
    public var reply: String
    public var model: String?

    public init(reply: String, model: String? = nil) {
        self.reply = reply
        self.model = model
    }
}

/// A turn the app holds on to and passes back as `history` (at most 10).
public struct AssistantTurn: Codable, Equatable, Sendable, Identifiable {
    public enum Role: String, Codable, Sendable { case user, assistant }

    public var id = UUID()
    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }

    enum CodingKeys: String, CodingKey { case role, text }
}

/// A failure worth showing as-is, in a bubble or spoken.
public struct AssistantError: LocalizedError, Equatable, Sendable {
    public let message: String
    public var errorDescription: String? { message }

    public init(message: String) { self.message = message }

    public static let unreachable = AssistantError(message: "I couldn't reach McFly just now. Check your connection and try again.")
    public static let signedOut = AssistantError(message: "Sign in to McFly first.")
}

/// Calls the `assistant` edge function over URLSession rather than
/// `supabase.functions`, so replies can stream token by token.
public struct AssistantClient: Sendable {
    public enum Mode: String, Sendable {
        /// One or two spoken sentences, no markdown.
        case quick
        /// May use short lists.
        case chat
    }

    public typealias TokenProvider = @Sendable () async throws -> String
    public static let historyLimit = 10

    private struct Body: Encodable {
        var message: String
        var mode: String
        var stream: Bool
        var history: [AssistantTurn]
        /// Left out when nil: the server falls back to `platform_settings.assistant_provider`.
        var provider: String?
    }

    private struct ErrorBody: Decodable { var error: String? }

    public let url: URL
    private let anonKey: String
    private let token: TokenProvider
    private let session: URLSession

    /// - Parameters:
    ///   - supabaseURL: the project URL; the function lives at /functions/v1/assistant.
    ///   - token: returns the caller's access token, refreshed if it expired.
    public init(supabaseURL: URL, anonKey: String, session: URLSession = .shared, token: @escaping TokenProvider) {
        self.url = supabaseURL.appendingPathComponent("functions/v1/assistant")
        self.anonKey = anonKey
        self.session = session
        self.token = token
    }

    /// Streams a reply, calling `onEvent` on the main actor for each event.
    /// Ends after `done` or `error`; throws only if the request itself fails.
    public func stream(_ message: String, mode: Mode, history: [AssistantTurn] = [], provider: AssistantProvider? = nil,
                       onEvent: @MainActor @Sendable (AssistantEvent) -> Void) async throws {
        let request = try await makeRequest(message, mode: mode, history: history, provider: provider, streaming: true)
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 16_384 { break }
            }
            throw Self.failure(status: status, body: body)
        }

        // Split lines by hand: `bytes.lines` drops the blank lines that end SSE events.
        var parser = SSEParser()
        var line: [UInt8] = []
        for try await byte in bytes {
            guard byte == UInt8(ascii: "\n") else {
                line.append(byte)
                continue
            }
            if line.last == UInt8(ascii: "\r") { line.removeLast() }
            let text = String(decoding: line, as: UTF8.self)
            line.removeAll(keepingCapacity: true)
            if let event = parser.feed(line: text).flatMap(Self.decode) {
                await onEvent(event)
                if event.isFinal { return }
            }
        }
        // The stream closed without a trailing blank line. A complete last event
        // still counts; a `done` cut off mid-way can't be read, so it's dropped
        // and the text that already streamed stays instead of becoming an error.
        if !line.isEmpty { _ = parser.feed(line: String(decoding: line, as: UTF8.self)) }
        if let raw = parser.finish(), let event = Self.decode(raw) {
            if case .error = event, raw.name == "done" { return }
            await onEvent(event)
        }
    }

    /// A whole reply at once. No streaming.
    public func ask(_ message: String, mode: Mode, history: [AssistantTurn] = [], provider: AssistantProvider? = nil) async throws -> AssistantReply {
        let request = try await makeRequest(message, mode: mode, history: history, provider: provider, streaming: false)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Self.failure(status: status, body: data) }
        return try JSONDecoder().decode(AssistantReply.self, from: data)
    }

    private func makeRequest(_ message: String, mode: Mode, history: [AssistantTurn], provider: AssistantProvider?,
                             streaming: Bool) async throws -> URLRequest {
        let token: String
        do {
            token = try await self.token()
        } catch {
            throw (error as? URLError) != nil ? AssistantError.unreachable : AssistantError.signedOut
        }
        var request = URLRequest(url: url, timeoutInterval: streaming ? 120 : 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(streaming ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(Body(
            message: String(message.prefix(4000)),
            mode: mode.rawValue,
            stream: streaming,
            history: Array(history.suffix(Self.historyLimit)),
            provider: provider?.rawValue))
        return request
    }

    private static func failure(status: Int, body: Data) -> AssistantError {
        let serverMessage = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error
        switch status {
        case 401:
            return AssistantError(message: "Your session ended. Sign in to McFly again.")
        case 403:
            return AssistantError(message: (serverMessage ?? "This account can't use the assistant.").sentenceCased)
        case 400..<500:
            return AssistantError(message: (serverMessage ?? "McFly didn't understand that request.").sentenceCased)
        case 500...:
            return AssistantError(message: serverMessage.map { $0.sentenceCased } ?? "McFly is having trouble right now. Try again in a moment.")
        default:
            return .unreachable
        }
    }

    private struct DeltaPayload: Decodable { var text: String }
    private struct ErrorPayload: Decodable { var message: String? }

    /// Maps a raw SSE event onto the spec's events; unknown names are skipped.
    public static func decode(_ raw: SSEParser.Event) -> AssistantEvent? {
        let data = Data(raw.data.utf8)
        let decoder = JSONDecoder()
        switch raw.name {
        case "delta":
            return (try? decoder.decode(DeltaPayload.self, from: data)).map { AssistantEvent.delta($0.text) }
        case "done":
            guard let reply = try? decoder.decode(AssistantReply.self, from: data) else {
                return .error("McFly sent a reply I couldn't read.")
            }
            return .done(reply)
        case "error":
            let message = (try? decoder.decode(ErrorPayload.self, from: data))?.message
            return .error(message ?? "Something went wrong. Try again.")
        default:
            return nil
        }
    }
}

/// Incremental parser for `text/event-stream`: feed it lines without their
/// line endings; a blank line completes an event.
public struct SSEParser: Sendable {
    public struct Event: Equatable, Sendable {
        public var name: String
        public var data: String

        public init(name: String, data: String) {
            self.name = name
            self.data = data
        }
    }

    private var name = ""
    private var dataLines: [String] = []

    public init() {}

    public mutating func feed(line: String) -> Event? {
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil }  // comment / keep-alive
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }
        switch field {
        case "event": name = String(value)
        case "data": dataLines.append(String(value))
        default: break  // id, retry
        }
        return nil
    }

    /// Flushes an event the stream ended without a blank line after.
    public mutating func finish() -> Event? { dispatch() }

    private mutating func dispatch() -> Event? {
        defer {
            name = ""
            dataLines = []
        }
        guard !dataLines.isEmpty else { return nil }
        return Event(name: name.isEmpty ? "message" : name, data: dataLines.joined(separator: "\n"))
    }
}

extension String {
    /// The server's messages are lowercase sentences ("admin only"); start them with a capital.
    public var sentenceCased: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
