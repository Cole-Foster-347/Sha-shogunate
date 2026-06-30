import Foundation
import Supabase
import Realtime

/// Canonical live chat for a match (CLAUDE.md §7 step 7, §8 Realtime).
/// Reads/sends `chat_message`; subscribes to live INSERTs via Supabase Realtime
/// (channel `chat:<matchId>`). RLS (0002) restricts everything to match participants.
/// Uses the Supabase Swift Realtime SDK — NOT OneShot's dead GetStream path.
@MainActor
class ChatService {
    private let supabase = SupabaseConfig.shared.client
    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    /// Existing messages for a match, oldest -> newest.
    func loadMessages(matchId: UUID) async throws -> [ChatMessageDTO] {
        try await supabase
            .from("chat_message")
            .select()
            .eq("match_id", value: matchId.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    /// Send a message (sender_user_id = auth.uid(), enforced by RLS).
    @discardableResult
    func sendMessage(matchId: UUID, body: String) async throws -> ChatMessageDTO {
        let me = try authService.getCurrentUserId()
        struct Insert: Encodable {
            let matchId: String
            let senderUserId: String
            let body: String
            enum CodingKeys: String, CodingKey {
                case matchId = "match_id"
                case senderUserId = "sender_user_id"
                case body
            }
        }
        let msg: ChatMessageDTO = try await supabase
            .from("chat_message")
            .insert(Insert(matchId: matchId.uuidString, senderUserId: me.uuidString, body: body))
            .select()
            .single()
            .execute()
            .value
        // TODO(analytics): fire chat_message_sent (§10) once an analytics SDK is wired.
        return msg
    }

    // MARK: - Realtime (§8: channel chat:<matchId>, listen to chat_message inserts)

    /// The realtime channel for a match. Register `messageInserts` BEFORE calling `subscribe()`.
    func channel(matchId: UUID) -> RealtimeChannelV2 {
        supabase.realtimeV2.channel("chat:\(matchId.uuidString)")
    }

    /// Stream of newly-inserted chat_message rows for this match.
    func messageInserts(on channel: RealtimeChannelV2, matchId: UUID) -> AsyncStream<ChatMessageDTO> {
        let changes = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "chat_message",
            filter: .eq("match_id", value: matchId.uuidString)
        )
        return AsyncStream { continuation in
            let task = Task {
                for await change in changes {
                    if let msg = try? change.decodeRecord(as: ChatMessageDTO.self, decoder: JSONDecoder()) {
                        continuation.yield(msg)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Canonical DTOs

/// Canonical `match` row (supabase/migrations/0001_init.sql).
/// (Named DuoMatchDTO to avoid OneShot's dead `MatchDTO` in MatchService.swift.)
struct DuoMatchDTO: Codable, Identifiable, Equatable {
    let id: UUID
    let duoA: UUID
    let duoB: UUID
    let status: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case duoA = "duo_a"
        case duoB = "duo_b"
        case status
        case createdAt = "created_at"
    }
}

/// Canonical `chat_message` row.
struct ChatMessageDTO: Codable, Identifiable, Equatable {
    let id: UUID
    let matchId: UUID
    let senderUserId: UUID
    let body: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case matchId = "match_id"
        case senderUserId = "sender_user_id"
        case body
        case createdAt = "created_at"
    }
}
