import Foundation
import Supabase

/// Canonical invite-code duo formation (Roomeet backend, migration 0005 + 0001).
///
/// Flow:
///   A (creator) calls `createInvite()` -> a unique code + a pending `duo_invite` row.
///   A shares the code; B (accepter) calls `acceptInvite(code:)` which, AT ACCEPTANCE,
///   creates the real `duo_profile` (member_a = creator, member_b = accepter), marks the
///   invite accepted, and sets B's own active duo. A then calls `confirmInviteAccepted(code:)`
///   to pick up the duo and set A's own active duo.
///
/// Writes ONLY to `duo_invite`, `duo_profile`, `app_user` — never the dead pairs/users tables.
///
/// RLS note: `app_user_self_update` only permits `id = auth.uid()`, so B physically cannot
/// set A's `active_duo_id` (that update would match 0 rows). Each user sets their own — B in
/// `acceptInvite`, A in `confirmInviteAccepted`.
@MainActor
class DuoInviteService {
    private let supabase = SupabaseConfig.shared.client
    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    // MARK: - Code generation

    /// Short human code: 4 letters + '-' + 4 digits, e.g. "PINE-4823".
    /// Excludes ambiguous characters (no O/0, I/1) for verbal sharing.
    private static func generateCode() -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ"
        let digits = "23456789"
        let letterPart = String((0..<4).map { _ in letters.randomElement()! })
        let digitPart = String((0..<4).map { _ in digits.randomElement()! })
        return "\(letterPart)-\(digitPart)"
    }

    // MARK: - Create (creator side, user A)

    /// Generate a unique code and insert a pending `duo_invite` owned by the current user.
    /// Retries on a unique-code collision. No `duo_profile` is created yet.
    /// - Parameter expiresIn: optional lifetime; defaults to 24h.
    /// - Returns: the created invite (with its code) to display to the creator.
    func createInvite(expiresIn: TimeInterval? = 24 * 60 * 60) async throws -> DuoInviteDTO {
        let creator = try authService.getCurrentUserId()
        let expiresAt = expiresIn.map { ISO8601DateFormatter().string(from: Date().addingTimeInterval($0)) }

        struct InviteInsert: Encodable {
            let code: String
            let creatorUserId: String
            let status: String
            let expiresAt: String?
            enum CodingKeys: String, CodingKey {
                case code
                case creatorUserId = "creator_user_id"
                case status
                case expiresAt = "expires_at"
            }
        }

        var lastError: Error?
        for _ in 0..<5 {
            let code = Self.generateCode()
            do {
                let invite: DuoInviteDTO = try await supabase
                    .from("duo_invite")
                    .insert(InviteInsert(
                        code: code,
                        creatorUserId: creator.uuidString,
                        status: "pending",
                        expiresAt: expiresAt
                    ))
                    .select()
                    .single()
                    .execute()
                    .value
                print("✅ duo_invite created: \(invite.code)")
                return invite
            } catch {
                lastError = error
                // 23505 = unique_violation on `code` -> regenerate and retry.
                let desc = "\(error)".lowercased()
                if desc.contains("23505") || desc.contains("duplicate") { continue }
                throw DuoInviteError.createFailed(error.localizedDescription)
            }
        }
        throw DuoInviteError.createFailed(lastError?.localizedDescription ?? "Could not generate a unique code")
    }

    // MARK: - Accept (accepter side, user B)

    /// Look up a pending invite by code and accept it: create the duo_profile,
    /// mark the invite accepted (linking the duo), and set B's own active duo.
    /// - Returns: the newly created duo_profile.
    func acceptInvite(code: String) async throws -> DuoProfileDTO {
        let accepter = try authService.getCurrentUserId()
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { throw DuoInviteError.codeNotFound }

        // 1. Look up the invite by code (RLS lets any authed user read a pending invite).
        let invites: [DuoInviteDTO] = try await supabase
            .from("duo_invite")
            .select()
            .eq("code", value: normalized)
            .execute()
            .value

        guard let invite = invites.first else { throw DuoInviteError.codeNotFound }
        guard invite.status == "pending" else { throw DuoInviteError.notPending }
        if let expiresAt = invite.expiresAt, expiresAt < Date() { throw DuoInviteError.expired }
        guard invite.creatorUserId != accepter else { throw DuoInviteError.cannotAcceptOwn }

        // 2. INSERT duo_profile. B is the inserter, so member_b = auth.uid() satisfies the
        //    duo_insert RLS (member_a OR member_b = auth.uid()); member_a is the creator.
        //    A duplicate active duo with the same partner trips the duo_unique_pair index (23505).
        struct DuoInsert: Encodable {
            let memberA: String
            let memberB: String
            enum CodingKeys: String, CodingKey {
                case memberA = "member_a"
                case memberB = "member_b"
            }
        }
        let duo: DuoProfileDTO
        do {
            duo = try await supabase
                .from("duo_profile")
                .insert(DuoInsert(memberA: invite.creatorUserId.uuidString, memberB: accepter.uuidString))
                .select()
                .single()
                .execute()
                .value
        } catch {
            if "\(error)".contains("23505") { throw DuoInviteError.alreadyPaired }
            throw DuoInviteError.acceptFailed(error.localizedDescription)
        }

        // 3. Mark the invite accepted and link the duo. The `status = pending` filter makes this
        //    idempotent — a second accept matches 0 rows and cannot relink.
        struct InviteAccept: Encodable {
            let status: String
            let acceptedByUserId: String
            let createdDuoId: String
            enum CodingKeys: String, CodingKey {
                case status
                case acceptedByUserId = "accepted_by_user_id"
                case createdDuoId = "created_duo_id"
            }
        }
        try await supabase
            .from("duo_invite")
            .update(InviteAccept(
                status: "accepted",
                acceptedByUserId: accepter.uuidString,
                createdDuoId: duo.id.uuidString
            ))
            .eq("code", value: normalized)
            .eq("status", value: "pending")
            .execute()

        // 4. Set B's own active duo (RLS: app_user_self_update permits id = auth.uid()).
        try await setOwnActiveDuo(userId: accepter, duoId: duo.id)

        // TODO(analytics): fire PostHog `duo_created` (CLAUDE.md §10) once an analytics SDK exists.
        print("✅ Invite \(normalized) accepted; duo_profile \(duo.id) created; B active duo set")
        return duo
    }

    // MARK: - Confirm (creator side, user A, after B accepted)

    /// A polls their own invite by code; if accepted, sets A's own active duo and returns the duo.
    /// Returns nil if the invite is still pending (B hasn't accepted yet).
    func confirmInviteAccepted(code: String) async throws -> DuoProfileDTO? {
        let creator = try authService.getCurrentUserId()
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        let invites: [DuoInviteDTO] = try await supabase
            .from("duo_invite")
            .select()
            .eq("code", value: normalized)
            .execute()
            .value
        guard let invite = invites.first else { throw DuoInviteError.codeNotFound }
        guard invite.status == "accepted", let duoId = invite.createdDuoId else {
            return nil   // still pending
        }

        let duos: [DuoProfileDTO] = try await supabase
            .from("duo_profile")
            .select()
            .eq("id", value: duoId.uuidString)
            .execute()
            .value
        guard let duo = duos.first else { throw DuoInviteError.acceptFailed("Duo not found for accepted invite") }

        try await setOwnActiveDuo(userId: creator, duoId: duo.id)
        print("✅ Creator confirmed invite \(normalized); A active duo set to \(duo.id)")
        return duo
    }

    // MARK: - Helpers

    /// Set the CURRENT user's active duo. RLS limits this to id = auth.uid().
    private func setOwnActiveDuo(userId: UUID, duoId: UUID) async throws {
        try await supabase
            .from("app_user")
            .update(["active_duo_id": duoId.uuidString])
            .eq("id", value: userId.uuidString)
            .execute()
    }
}

// MARK: - DTOs

/// Canonical `duo_invite` row (supabase/migrations/0005_duo_invite.sql).
struct DuoInviteDTO: Codable {
    let id: UUID
    let code: String
    let creatorUserId: UUID
    let status: String
    let acceptedByUserId: UUID?
    let createdDuoId: UUID?
    let createdAt: Date
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case creatorUserId = "creator_user_id"
        case status
        case acceptedByUserId = "accepted_by_user_id"
        case createdDuoId = "created_duo_id"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

/// Canonical `duo_profile` row (supabase/migrations/0001_init.sql).
struct DuoProfileDTO: Codable {
    let id: UUID
    let memberA: UUID
    let memberB: UUID
    let photos: [String]
    let bio: String?
    let activeWeek: Int
    let reliabilityScore: Int
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case memberA = "member_a"
        case memberB = "member_b"
        case photos
        case bio
        case activeWeek = "active_week"
        case reliabilityScore = "reliability_score"
        case status
        case createdAt = "created_at"
    }
}

// MARK: - Errors

enum DuoInviteError: LocalizedError {
    case createFailed(String)
    case acceptFailed(String)
    case codeNotFound
    case notPending
    case expired
    case cannotAcceptOwn
    case alreadyPaired

    var errorDescription: String? {
        switch self {
        case .createFailed(let m): return "Couldn't create an invite: \(m)"
        case .acceptFailed(let m): return "Couldn't join the duo: \(m)"
        case .codeNotFound: return "That code doesn't match an invite."
        case .notPending: return "That invite has already been used or cancelled."
        case .expired: return "That invite has expired."
        case .cannotAcceptOwn: return "You can't accept your own invite — share it with a friend."
        case .alreadyPaired: return "You're already in a duo with this person."
        }
    }
}
