import Foundation
import Supabase

/// Pending-likes tray data source (CLAUDE.md §7 step 5, §2 both-must-like).
///
/// Surfaces the targets my PARTNER liked but I haven't yet — the ones waiting on
/// my confirmation to become a `duo_like`. CONFIRMING is just inserting my own
/// `like_intent` (reuse `LikeService.like`); this service only FETCHES.
///
/// Strictly scoped to my active duo (§4). Reads `like_intent` (RLS lets me read my
/// own duo's intents via is_duo_member(from_duo_id)), `block`, and `duo_profile`.
/// Only the authenticated client — no service-role key on device.
@MainActor
final class PendingLikesService {
    private let supabase = SupabaseConfig.shared.client
    private let authService: AuthService
    private let browseService: BrowseService

    init(authService: AuthService, browseService: BrowseService) {
        self.authService = authService
        self.browseService = browseService
    }

    /// Target duos my partner liked but I have NOT — pending my confirmation.
    /// Excludes targets I've already liked, blocked targets, and non-active duos.
    func pendingLikeTargets() async throws -> [DuoProfileDTO] {
        let me = try authService.getCurrentUserId()
        guard let myDuo = try await browseService.fetchActiveDuo() else { return [] }
        let partner = (myDuo.memberA == me) ? myDuo.memberB : myDuo.memberA

        // All intents from my active duo (both members). RLS scopes this to my duo.
        struct IntentRow: Decodable {
            let targetDuoId: UUID
            let actorUserId: UUID
            enum CodingKeys: String, CodingKey {
                case targetDuoId = "target_duo_id"
                case actorUserId = "actor_user_id"
            }
        }
        let intents: [IntentRow] = try await supabase
            .from("like_intent")
            .select("target_duo_id, actor_user_id")
            .eq("from_duo_id", value: myDuo.id.uuidString)
            .execute()
            .value

        let partnerTargets = Set(intents.filter { $0.actorUserId == partner }.map(\.targetDuoId))
        let myTargets = Set(intents.filter { $0.actorUserId == me }.map(\.targetDuoId))
        let pending = partnerTargets.subtracting(myTargets)
        guard !pending.isEmpty else { return [] }

        // Drop targets my active duo has blocked.
        struct BlockRow: Decodable {
            let blockedDuoId: UUID
            enum CodingKeys: String, CodingKey { case blockedDuoId = "blocked_duo_id" }
        }
        let blocks: [BlockRow] = try await supabase
            .from("block")
            .select("blocked_duo_id")
            .eq("blocker_duo_id", value: myDuo.id.uuidString)
            .execute()
            .value
        let wanted = pending.subtracting(blocks.map(\.blockedDuoId))
        guard !wanted.isEmpty else { return [] }

        let duos: [DuoProfileDTO] = try await supabase
            .from("duo_profile")
            .select()
            .eq("status", value: "active")
            .in("id", values: wanted.map(\.uuidString))
            .execute()
            .value
        return duos
    }
}
