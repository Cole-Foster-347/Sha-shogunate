import Foundation
import Supabase

/// Canonical, READ-ONLY Browse data source (Roomeet backend).
///
/// Fetches other active duos for the card stack, scoped to the current user's active duo
/// (CLAUDE.md §4 active-duo scoping), excluding the user's own duo(s) and any duo their
/// active duo has blocked. Reads only `duo_profile` / `app_user` / `block` — never OneShot's
/// dead `pairs`/`users` tables. No writes (liking is the next ticket).
@MainActor
class BrowseService {
    private let supabase = SupabaseConfig.shared.client
    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    /// The current user's active duo id — the identity we browse as (§4).
    func currentActiveDuoId() async throws -> UUID? {
        let me = try authService.getCurrentUserId()
        struct Row: Decodable {
            let activeDuoId: UUID?
            enum CodingKeys: String, CodingKey { case activeDuoId = "active_duo_id" }
        }
        let rows: [Row] = try await supabase
            .from("app_user")
            .select("active_duo_id")
            .eq("id", value: me.uuidString)
            .execute()
            .value
        return rows.first?.activeDuoId
    }

    /// The current user's active duo_profile (for session resume), or nil if they have none.
    func fetchActiveDuo() async throws -> DuoProfileDTO? {
        guard let activeDuoId = try await currentActiveDuoId() else { return nil }
        let rows: [DuoProfileDTO] = try await supabase
            .from("duo_profile")
            .select()
            .eq("id", value: activeDuoId.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Fetch the browseable card stack for the current user.
    ///
    /// Equivalent SQL WHERE:
    ///   status = 'active'
    ///   AND member_a <> :me AND member_b <> :me     -- exclude duos I'm a member of (incl. my own)
    ///   AND id <> :myActiveDuoId                     -- belt-and-suspenders own-duo exclusion
    ///   AND id NOT IN (SELECT blocked_duo_id FROM block WHERE blocker_duo_id = :myActiveDuoId)
    func fetchBrowseableDuos() async throws -> [DuoProfileDTO] {
        let me = try authService.getCurrentUserId()
        let activeDuoId = try await currentActiveDuoId()

        // Blocked targets: duos my active duo has blocked.
        var blockedIds: [String] = []
        if let activeDuoId {
            struct BlockRow: Decodable {
                let blockedDuoId: UUID
                enum CodingKeys: String, CodingKey { case blockedDuoId = "blocked_duo_id" }
            }
            let blocks: [BlockRow] = try await supabase
                .from("block")
                .select("blocked_duo_id")
                .eq("blocker_duo_id", value: activeDuoId.uuidString)
                .execute()
                .value
            blockedIds = blocks.map { $0.blockedDuoId.uuidString }
        }

        var query = supabase
            .from("duo_profile")
            .select()
            .eq("status", value: "active")
            .neq("member_a", value: me.uuidString)
            .neq("member_b", value: me.uuidString)

        if let activeDuoId {
            query = query.neq("id", value: activeDuoId.uuidString)
        }
        if !blockedIds.isEmpty {
            // id NOT IN (blocked) — PostgREST: id=not.in.(uuid,uuid,...)
            query = query.not("id", operator: .in, value: "(\(blockedIds.joined(separator: ",")))")
        }

        let duos: [DuoProfileDTO] = try await query
            .order("created_at", ascending: true)
            .execute()
            .value
        return duos
    }
}
