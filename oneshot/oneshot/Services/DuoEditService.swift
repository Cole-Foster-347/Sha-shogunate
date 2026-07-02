import Foundation
import Supabase

/// Canonical edit-duo data source (Roomeet backend) — bio + interests for the
/// user's ACTIVE duo (CLAUDE.md §4 active-duo scoping). Photos live in
/// `DuoPhotoService`; report/block/leave-duo are separate tickets.
///
/// Writes only `duo_profile.bio` and `duo_interest`; reads `interest_tag`.
/// Authenticated client only — no service-role key on device (§4.1). RLS enforces
/// membership: `duo_update_members` (bio) and `duo_interest_write` (interests) both
/// gate on `is_duo_member`, so a non-member's PATCH/insert/delete is rejected.
/// `interest_tag` is a curated, read-only vocabulary (`interest_read` is SELECT-only
/// for authed users) — the client picks from existing tags, never creates new ones.
@MainActor
final class DuoEditService {
    private let supabase = SupabaseConfig.shared.client
    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    // MARK: - Bio

    /// PATCH the active duo's bio. Empty/whitespace -> null. Trimmed and length-capped.
    /// RLS `duo_update_members` allows either member; a non-member update affects 0 rows.
    func updateBio(duoId: UUID, bio: String) async throws {
        let trimmed = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = String(trimmed.prefix(Self.maxBioLength))

        struct BioPatch: Encodable { let bio: String? }
        try await supabase
            .from("duo_profile")
            .update(BioPatch(bio: capped.isEmpty ? nil : capped))
            .eq("id", value: duoId.uuidString)
            .execute()
    }

    /// Reasonable bio cap (§7.1 "trim/limit length reasonably").
    static let maxBioLength = 500

    // MARK: - Interests

    /// The full curated tag vocabulary (choices to pick from).
    func allTags() async throws -> [InterestTagDTO] {
        try await supabase
            .from("interest_tag")
            .select()
            .order("label", ascending: true)
            .execute()
            .value
    }

    /// The tag ids currently linked to this duo (from the `duo_interest` join).
    func interestTagIds(forDuo duoId: UUID) async throws -> Set<UUID> {
        struct Row: Decodable {
            let tagId: UUID
            enum CodingKeys: String, CodingKey { case tagId = "tag_id" }
        }
        let rows: [Row] = try await supabase
            .from("duo_interest")
            .select("tag_id")
            .eq("duo_id", value: duoId.uuidString)
            .execute()
            .value
        return Set(rows.map { $0.tagId })
    }

    /// Link a tag to the duo (insert `duo_interest`). Idempotent: a duplicate
    /// (PK duo_id+tag_id) is swallowed. RLS `duo_interest_write` gates on membership.
    func addInterest(duoId: UUID, tagId: UUID) async throws {
        struct DuoInterestInsert: Encodable {
            let duoId: String
            let tagId: String
            enum CodingKeys: String, CodingKey {
                case duoId = "duo_id"
                case tagId = "tag_id"
            }
        }
        do {
            try await supabase
                .from("duo_interest")
                .insert(DuoInterestInsert(duoId: duoId.uuidString, tagId: tagId.uuidString))
                .execute()
        } catch {
            let desc = "\(error)".lowercased()
            guard desc.contains("23505") || desc.contains("duplicate") else { throw error }
            // already linked — no-op
        }
    }

    /// Unlink a tag from the duo (delete the `duo_interest` row).
    func removeInterest(duoId: UUID, tagId: UUID) async throws {
        try await supabase
            .from("duo_interest")
            .delete()
            .eq("duo_id", value: duoId.uuidString)
            .eq("tag_id", value: tagId.uuidString)
            .execute()
    }
}

/// Canonical `interest_tag` row (supabase/migrations/0001_init.sql).
struct InterestTagDTO: Codable, Identifiable, Hashable {
    let id: UUID
    let label: String
}
