// SPDX-License-Identifier: Apache-2.0
import ExplorerDomain

/// Optional explicit read-only history operation on an admitted live candidate.
public protocol RevisionHistoryProvider: ExplorerProvider {
    func history(_ input: RevisionHistoryInput) async throws -> RevisionHistoryPage
}
