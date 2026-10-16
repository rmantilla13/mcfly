import Foundation
import Supabase

/// The admin RPCs (spec §1.6) and the `admin` function (§2.3) the app uses.
/// A protocol so previews and the demo can answer without a backend.
public protocol AdminService: Sendable {
    func isPlatformAdmin() async throws -> Bool
    func listDevices() async throws -> [Device]
    func renameDevice(_ id: UUID, name: String) async throws
    func revokeDevice(_ id: UUID) async throws
    func listAgents() async throws -> [Agent]
    func createAgent(name: String, kind: Agent.Kind, color: String) async throws -> CreatedAgent
    func rotateAgentKey(_ id: UUID) async throws -> String
    func revokeAgent(_ id: UUID) async throws
    func deleteAgent(_ id: UUID) async throws
    func settings() async throws -> PlatformSettings
    func updateSettings(displayName: String?, timezone: String?, assistantProvider: AssistantProvider?) async throws -> PlatformSettings
    /// `admin_project_updates`: more of a project's timeline than the feed embeds.
    func projectUpdates(_ projectId: UUID, limit: Int) async throws -> [ProjectUpdate]
    /// Made dashboards (DashboardBuilding.swift): what a part can pull from,
    /// a recipe drawn without saving, and saving one (a new board without an id).
    func dashboardSources() async throws -> DashboardSourceOptions
    func previewDashboard(_ parts: [DashboardPart]) async throws -> [DashboardWidget]
    func saveDashboard(id: UUID?, title: String, subtitle: String?, template: String?, parts: [DashboardPart]) async throws -> UUID
}

public struct SupabaseAdminService: AdminService {
    let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func isPlatformAdmin() async throws -> Bool {
        let data = try await client.rpc("is_platform_admin").execute().data
        return try JSONDecoder.mcfly.decode(Bool.self, from: data)
    }

    public func listDevices() async throws -> [Device] {
        try await rows("admin_list_devices")
    }

    public func renameDevice(_ id: UUID, name: String) async throws {
        try await client.rpc("admin_rename_device", params: ["device": id.lowercased, "name": name]).execute()
    }

    /// Through the `admin` function: removing the display's auth user needs the
    /// service role, which only the function has.
    public func revokeDevice(_ id: UUID) async throws {
        struct Body: Encodable {
            var action = "revoke_device"
            var device_id: String
        }
        try await client.functions.invoke("admin", options: FunctionInvokeOptions(body: Body(device_id: id.lowercased)))
    }

    public func listAgents() async throws -> [Agent] {
        try await rows("admin_list_agents")
    }

    public func createAgent(name: String, kind: Agent.Kind, color: String) async throws -> CreatedAgent {
        let created: [CreatedAgent] = try await rows("admin_create_agent",
                                                     params: ["name": name, "kind": kind.rawValue, "color": color])
        guard let agent = created.first else { throw McFlyError.message("The server made no agent.") }
        return agent
    }

    public func rotateAgentKey(_ id: UUID) async throws -> String {
        let data = try await client.rpc("admin_rotate_agent_key", params: ["agent": id.lowercased]).execute().data
        return try JSONDecoder.mcfly.decode(String.self, from: data)
    }

    public func revokeAgent(_ id: UUID) async throws {
        try await client.rpc("admin_revoke_agent", params: ["agent": id.lowercased]).execute()
    }

    public func deleteAgent(_ id: UUID) async throws {
        try await client.rpc("admin_delete_agent", params: ["agent": id.lowercased]).execute()
    }

    public func settings() async throws -> PlatformSettings {
        let data = try await client.rpc("admin_get_settings").execute().data
        return try JSONDecoder.mcfly.decode(PlatformSettings.self, from: data)
    }

    /// Nil leaves a setting as it is (the RPC's own rule).
    public func updateSettings(displayName: String?, timezone: String?, assistantProvider: AssistantProvider?) async throws -> PlatformSettings {
        struct Params: Encodable {
            var display_name: String?
            var timezone: String?
            var assistant_provider: String?
        }
        let params = Params(display_name: displayName, timezone: timezone, assistant_provider: assistantProvider?.rawValue)
        let data = try await client.rpc("admin_update_settings", params: params).execute().data
        return try JSONDecoder.mcfly.decode(PlatformSettings.self, from: data)
    }

    public func projectUpdates(_ projectId: UUID, limit: Int) async throws -> [ProjectUpdate] {
        struct Params: Encodable {
            var project: String
            var lim: Int
        }
        let data = try await client.rpc("admin_project_updates", params: Params(project: projectId.lowercased, lim: limit)).execute().data
        return try JSONDecoder.mcfly.decode([ProjectUpdate].self, from: data)
    }

    private func rows<T: Decodable>(_ function: String, params: [String: String] = [:]) async throws -> [T] {
        let data = try await client.rpc(function, params: params).execute().data
        return try JSONDecoder.mcfly.decode([T].self, from: data)
    }
}

extension UUID {
    /// The functions compare ids as strings, and Postgres writes them lowercase.
    public var lowercased: String { uuidString.lowercased() }
}
