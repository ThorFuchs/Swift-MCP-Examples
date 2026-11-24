// SPDX-License-Identifier: Apache-2.0
import Foundation
import ExplorerDomain
import ExplorerMCP
import MCPClient

/// A user-selected execution route, independent of the source profile.
public enum ResearchExecutionMode: String, CaseIterable, Sendable {
    case direct = "Direct"
    case mcp = "Via MCP"
}

/// An interactive reader adapter using the same public SDK as Explore MCP.
/// Owned by one serial ResearchController driver. Preparation is lazy and
/// occurs only on the first explicit research operation. Never falls back.
public actor RunBoundResearchClient: ResearchClient {
    private let client: MCPResearchClient
    private let isCurrent: @MainActor @Sendable () -> Bool
    private var prepared = false

    /// The caller supplies a readiness/identity check for the selected host run.
    public init(endpoint: ServerEndpoint, profile: SourceProfile,
                isCurrent: @escaping @MainActor @Sendable () -> Bool) throws {
        self.isCurrent = isCurrent
        client = MCPResearchClient(client: Client(transport: try MCPJourneyController.httpTransport(endpoint)), profile: profile)
    }

    private func check() async throws {
        try Task.checkCancellation()
        guard await isCurrent() else { throw MCPResearchFailure.transport }
        try Task.checkCancellation()
    }

    private func ready() async throws {
        try await check()
        if !prepared {
            _ = try await client.prepare()
            try await check()
            prepared = true
        }
    }

    public func search(_ input: SearchInput) async throws -> SearchPage {
        try await ready()
        let result = try await client.search(input)
        try await check()
        return result
    }

    public func outline(_ input: OutlineInput) async throws -> Outline {
        try await ready()
        let result = try await client.outline(input)
        try await check()
        return result
    }

    public func section(_ input: SectionInput) async throws -> SectionPassage {
        try await ready()
        let result = try await client.section(input)
        try await check()
        return result
    }

    public func references(_ input: ReferencesInput) async throws -> SectionReferences {
        try await ready()
        let result = try await client.references(input)
        try await check()
        return result
    }
}
