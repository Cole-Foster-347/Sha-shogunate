import Foundation
import Supabase

/// Canonical two-stage "like" (CLAUDE.md §4 both-must-like, §7 steps 5–6).
///
/// A like is per-USER: each tap inserts ONE `like_intent` (from_duo_id = our active duo,
/// actor_user_id = auth.uid()). The LIVE DB triggers (migration 0004) do the rest:
///   - when BOTH members of a duo have a like_intent toward the same target -> `duo_like`
///   - when two duos mutually `duo_like` (7-day guard) -> `match`
/// We do NOT reimplement any of that here — we only insert like_intent.
///
/// Writes only `like_intent` — never OneShot's dead tables.
@MainActor
class LikeService {
    private let supabase = SupabaseConfig.shared.client
    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    /// Record the current user's like toward a target duo.
    /// - Parameters:
    ///   - fromDuoId: the liker's active duo (must be one I'm a member of — RLS enforces this).
    ///   - targetDuoId: the duo being liked.
    /// - Returns: true if a new like_intent was inserted; false if it already existed (dup tap).
    @discardableResult
    func like(fromDuoId: UUID, targetDuoId: UUID) async throws -> Bool {
        let me = try authService.getCurrentUserId()

        struct LikeIntentInsert: Encodable {
            let fromDuoId: String
            let targetDuoId: String
            let actorUserId: String
            enum CodingKeys: String, CodingKey {
                case fromDuoId = "from_duo_id"
                case targetDuoId = "target_duo_id"
                case actorUserId = "actor_user_id"
            }
        }

        do {
            try await supabase
                .from("like_intent")
                .insert(LikeIntentInsert(
                    fromDuoId: fromDuoId.uuidString,
                    targetDuoId: targetDuoId.uuidString,
                    actorUserId: me.uuidString
                ))
                .execute()
            // TODO(analytics): fire like_intent_sent (§10) once an analytics SDK is wired.
            print("✅ like_intent: \(fromDuoId) -> \(targetDuoId) by \(me)")
            return true
        } catch {
            // unique(from_duo_id, target_duo_id, actor_user_id) -> 23505 on a duplicate tap.
            let desc = "\(error)".lowercased()
            if desc.contains("23505") || desc.contains("duplicate") {
                print("ℹ️ already liked \(targetDuoId)")
                return false
            }
            throw LikeError.likeFailed(error.localizedDescription)
        }
    }
}

enum LikeError: LocalizedError {
    case likeFailed(String)
    case noActiveDuo

    var errorDescription: String? {
        switch self {
        case .likeFailed(let m): return "Couldn't record your like: \(m)"
        case .noActiveDuo: return "You need an active duo before you can like."
        }
    }
}
