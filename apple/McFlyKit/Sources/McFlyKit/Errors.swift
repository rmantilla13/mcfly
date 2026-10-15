import Foundation
import Supabase

/// A failure with a sentence for the person, as the server wrote it where it
/// did ("admin only", "code already used").
public enum McFlyError: LocalizedError, Equatable {
    case message(String)

    public var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }

    /// The best sentence for any error the clients throw.
    public static func describe(_ error: Error) -> String {
        if let error = error as? McFlyError { return error.errorDescription ?? "Something went wrong." }
        if let error = error as? AssistantError { return error.message }
        // The RPCs raise short lowercase sentences meant for people.
        if let error = error as? PostgrestError { return error.message.sentenceCased }
        // Edge functions answer a 4xx/5xx with {"error": "..."}; show that, not the status code.
        struct FunctionErrorBody: Decodable { let error: String }
        if let functionsError = error as? FunctionsError, case let .httpError(code, data) = functionsError {
            if let body = try? JSONDecoder().decode(FunctionErrorBody.self, from: data) {
                return body.error.sentenceCased
            }
            return "The server answered with an error (\(code))."
        }
        if error is URLError || (error as NSError).domain == NSURLErrorDomain {
            return "McFly couldn't be reached. Check your connection and try again."
        }
        if error is DecodingError {
            return "McFly sent something this version of the app couldn't read."
        }
        return error.localizedDescription.sentenceCased
    }
}
