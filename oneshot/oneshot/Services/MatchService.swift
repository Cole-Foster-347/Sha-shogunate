import Foundation
import Supabase

/// Service responsible for matching, swiping, and match management operations
@MainActor
class MatchService {
    // MARK: - Properties

    private let supabase = SupabaseConfig.shared.client
    private let authService: AuthService
    private let userService: UserService
    private let pairService: PairService

    // MARK: - Initialization

    init(authService: AuthService, userService: UserService, pairService: PairService) {
        self.authService = authService
        self.userService = userService
        self.pairService = pairService
    }

    // MARK: - Canonical Matches (Roomeet backend)
    // Reads the canonical `match` table. RLS (match_read) already restricts visibility
    // to participants. Does not touch OneShot's dead swipe/pairs schema below.

    /// Active matches involving the current user's active duo (CLAUDE.md §4/§7).
    func fetchActiveMatches() async throws -> [DuoMatchDTO] {
        let me = try authService.getCurrentUserId()
        struct Row: Decodable {
            let activeDuoId: UUID?
            enum CodingKeys: String, CodingKey { case activeDuoId = "active_duo_id" }
        }
        let rows: [Row] = try await supabase
            .from("app_user").select("active_duo_id")
            .eq("id", value: me.uuidString)
            .execute().value
        guard let activeDuoId = rows.first?.activeDuoId else { return [] }

        return try await supabase
            .from("match")
            .select()
            .eq("status", value: "active")
            .or("duo_a.eq.\(activeDuoId.uuidString),duo_b.eq.\(activeDuoId.uuidString)")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    // MARK: - Swiping

    /// Record a swipe action
    /// - Parameters:
    ///   - swiperPairId: The pair doing the swiping
    ///   - swiperUserId: The specific user who swiped
    ///   - swipedPairId: The pair being swiped on
    ///   - direction: Swipe direction (left, right, super)
    /// - Returns: Match if both pairs swiped right, nil otherwise
    func recordSwipe(
        swiperPairId: UUID,
        swipedPairId: UUID,
        swiperUserId: UUID,
        direction: SwipeAction
    ) async throws -> Match? {
        let directionString: String
        switch direction {
        case .like:
            directionString = "right"
        case .pass:
            directionString = "left"
        case .superLike:
            directionString = "super"
        }

        let swipeData: [String: AnyEncodable] = [
            "swiper_pair_id": AnyEncodable(swiperPairId.uuidString),
            "swiped_pair_id": AnyEncodable(swipedPairId.uuidString),
            "swiper_user_id": AnyEncodable(swiperUserId.uuidString),
            "direction": AnyEncodable(directionString)
        ]

        do {
            try await supabase
                .from("swipes")
                .insert(swipeData)
                .execute()

            print("✅ Swipe recorded: \(direction)")

            // If it's a like or superlike, check for match
            if direction == .like || direction == .superLike {
                return try await checkForMatch(pair1Id: swiperPairId, pair2Id: swipedPairId)
            }

            return nil

        } catch {
            print("❌ Record swipe error: \(error)")
            throw MatchError.swipeFailed(error.localizedDescription)
        }
    }

    /// Check if both pairs have swiped right on each other
    /// - Parameters:
    ///   - pair1Id: First pair's ID
    ///   - pair2Id: Second pair's ID
    /// - Returns: Match if both swiped right, nil otherwise
    private func checkForMatch(pair1Id: UUID, pair2Id: UUID) async throws -> Match? {
        do {
            // Check if pair2 has swiped right on pair1
            let reciprocalSwipes: [SwipeDTO] = try await supabase
                .from("swipes")
                .select()
                .eq("swiper_pair_id", value: pair2Id.uuidString)
                .eq("swiped_pair_id", value: pair1Id.uuidString)
                .in("direction", values: ["right", "super"])
                .execute()
                .value

            guard !reciprocalSwipes.isEmpty else {
                print("ℹ️ No reciprocal swipe yet")
                return nil
            }

            // It's a match! Create match record
            return try await createMatch(pair1Id: pair1Id, pair2Id: pair2Id)

        } catch {
            print("❌ Check for match error: \(error)")
            throw MatchError.checkFailed(error.localizedDescription)
        }
    }

    /// Create a match between two pairs
    /// - Parameters:
    ///   - pair1Id: First pair's ID
    ///   - pair2Id: Second pair's ID
    /// - Returns: Created Match
    private func createMatch(pair1Id: UUID, pair2Id: UUID) async throws -> Match {
        let matchData: [String: AnyEncodable] = [
            "pair1_id": AnyEncodable(pair1Id.uuidString),
            "pair2_id": AnyEncodable(pair2Id.uuidString),
            "status": AnyEncodable("active")
        ]

        do {
            let response: MatchDTO = try await supabase
                .from("matches")
                .insert(matchData)
                .select()
                .single()
                .execute()
                .value

            print("✅ Match created: \(response.id)")

            // Return complete match with duo data
            return try await getMatch(id: response.id)

        } catch {
            print("❌ Create match error: \(error)")
            throw MatchError.createFailed(error.localizedDescription)
        }
    }

    // MARK: - Match Retrieval

    /// Get a match by ID
    /// - Parameter id: Match's ID
    /// - Returns: Match model
    func getMatch(id: UUID) async throws -> Match {
        do {
            let matchDTO: MatchDTO = try await supabase
                .from("matches")
                .select()
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value

            let duo1 = try await pairService.getPair(id: matchDTO.pair1Id)
            let duo2 = try await pairService.getPair(id: matchDTO.pair2Id)

            // Get last message if exists
            var lastMessageSummary: MessageSummary?
            if let lastMessage = try? await getLastMessage(matchId: id) {
                lastMessageSummary = lastMessage
            }

            return Match(
                id: matchDTO.id,
                duo1Id: matchDTO.pair1Id,
                duo2Id: matchDTO.pair2Id,
                duo1: duo1,
                duo2: duo2,
                createdAt: matchDTO.matchedAt,
                lastMessageAt: matchDTO.lastMessageAt,
                lastMessageSummary: lastMessageSummary,
                unreadCount: 0 // TODO: Calculate unread count
            )

        } catch {
            print("❌ Get match error: \(error)")
            throw MatchError.fetchFailed(error.localizedDescription)
        }
    }

    /// Get all matches for a pair
    /// - Parameter pairId: Pair's ID
    /// - Returns: Array of Match models
    func getMatches(pairId: UUID) async throws -> [Match] {
        do {
            let response: [MatchDTO] = try await supabase
                .from("matches")
                .select()
                .or("pair1_id.eq.\(pairId.uuidString),pair2_id.eq.\(pairId.uuidString)")
                .eq("status", value: "active")
                .order("matched_at", ascending: false)
                .execute()
                .value

            var matches: [Match] = []

            for matchDTO in response {
                let duo1 = try await pairService.getPair(id: matchDTO.pair1Id)
                let duo2 = try await pairService.getPair(id: matchDTO.pair2Id)

                // Get last message if exists
                var lastMessageSummary: MessageSummary?
                if let lastMessage = try? await getLastMessage(matchId: matchDTO.id) {
                    lastMessageSummary = lastMessage
                }

                matches.append(Match(
                    id: matchDTO.id,
                    duo1Id: matchDTO.pair1Id,
                    duo2Id: matchDTO.pair2Id,
                    duo1: duo1,
                    duo2: duo2,
                    createdAt: matchDTO.matchedAt,
                    lastMessageAt: matchDTO.lastMessageAt,
                    lastMessageSummary: lastMessageSummary,
                    unreadCount: 0 // TODO: Calculate unread count
                ))
            }

            return matches

        } catch {
            print("❌ Get matches error: \(error)")
            throw MatchError.fetchFailed(error.localizedDescription)
        }
    }

    /// Get matches for the current user's pair
    /// - Returns: Array of Match models
    func getCurrentMatches() async throws -> [Match] {
        guard let currentPair = try await pairService.getCurrentPair() else {
            return []
        }

        return try await getMatches(pairId: currentPair.id)
    }

    // MARK: - Match Management

    /// Unmatch/remove a match
    /// - Parameter matchId: Match's ID
    func unmatch(matchId: UUID) async throws {
        do {
            try await supabase
                .from("matches")
                .update(["status": AnyEncodable("archived")])
                .eq("id", value: matchId.uuidString)
                .execute()

            print("✅ Match unmatched: \(matchId)")

        } catch {
            print("❌ Unmatch error: \(error)")
            throw MatchError.unmatchFailed(error.localizedDescription)
        }
    }

    /// Block a match
    /// - Parameter matchId: Match's ID
    func blockMatch(matchId: UUID) async throws {
        do {
            try await supabase
                .from("matches")
                .update(["status": AnyEncodable("blocked")])
                .eq("id", value: matchId.uuidString)
                .execute()

            print("✅ Match blocked: \(matchId)")

        } catch {
            print("❌ Block match error: \(error)")
            throw MatchError.blockFailed(error.localizedDescription)
        }
    }

    // MARK: - Messages (Basic)

    /// Get the last message for a match
    /// - Parameter matchId: Match's ID
    /// - Returns: MessageSummary if exists
    private func getLastMessage(matchId: UUID) async throws -> MessageSummary? {
        do {
            let response: [MessageDTO] = try await supabase
                .from("messages")
                .select()
                .eq("match_id", value: matchId.uuidString)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            guard let messageDTO = response.first else {
                return nil
            }

            let sender = try await userService.getUser(id: messageDTO.senderUserId)

            return MessageSummary(
                id: messageDTO.id,
                senderId: messageDTO.senderUserId,
                senderName: sender.firstName,
                content: messageDTO.content,
                messageType: MessageType(rawValue: messageDTO.messageType) ?? .text,
                createdAt: messageDTO.createdAt
            )

        } catch {
            return nil
        }
    }

    /// Send a message to a match
    /// - Parameters:
    ///   - matchId: Match's ID
    ///   - senderId: Sender's user ID
    ///   - content: Message content
    ///   - type: Message type
    func sendMessage(
        matchId: UUID,
        senderId: UUID,
        content: String,
        type: MessageType = .text
    ) async throws {
        let messageData: [String: AnyEncodable] = [
            "match_id": AnyEncodable(matchId.uuidString),
            "sender_user_id": AnyEncodable(senderId.uuidString),
            "content": AnyEncodable(content),
            "message_type": AnyEncodable(type.rawValue),
            "is_read": AnyEncodable(false)
        ]

        do {
            try await supabase
                .from("messages")
                .insert(messageData)
                .execute()

            // Update match's last_message_at
            try await supabase
                .from("matches")
                .update(["last_message_at": AnyEncodable(ISO8601DateFormatter().string(from: Date()))])
                .eq("id", value: matchId.uuidString)
                .execute()

            print("✅ Message sent")

        } catch {
            print("❌ Send message error: \(error)")
            throw MatchError.sendMessageFailed(error.localizedDescription)
        }
    }

    /// Get messages for a match
    /// - Parameters:
    ///   - matchId: Match's ID
    ///   - limit: Maximum number of messages to return
    /// - Returns: Array of Message models
    func getMessages(matchId: UUID, limit: Int = 50) async throws -> [Message] {
        do {
            let response: [MessageDTO] = try await supabase
                .from("messages")
                .select()
                .eq("match_id", value: matchId.uuidString)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value

            var messages: [Message] = []

            for messageDTO in response {
                let sender = try await userService.getUser(id: messageDTO.senderUserId)

                messages.append(Message(
                    id: messageDTO.id,
                    matchId: matchId,
                    senderId: messageDTO.senderUserId,
                    senderSummary: UserSummary(from: sender),
                    content: messageDTO.content,
                    messageType: MessageType(rawValue: messageDTO.messageType) ?? .text,
                    createdAt: messageDTO.createdAt,
                    isRead: messageDTO.isRead
                ))
            }

            return messages.reversed() // Return in chronological order

        } catch {
            print("❌ Get messages error: \(error)")
            throw MatchError.fetchMessagesFailed(error.localizedDescription)
        }
    }

    /// Mark messages as read
    /// - Parameters:
    ///   - messageIds: Array of message IDs
    func markMessagesAsRead(messageIds: [UUID]) async throws {
        guard !messageIds.isEmpty else { return }

        do {
            let ids = messageIds.map { $0.uuidString }

            try await supabase
                .from("messages")
                .update(["is_read": AnyEncodable(true)])
                .in("id", values: ids)
                .execute()

            print("✅ Messages marked as read: \(messageIds.count)")

        } catch {
            print("❌ Mark as read error: \(error)")
            throw MatchError.markReadFailed(error.localizedDescription)
        }
    }
}

// MARK: - DTOs

struct MatchDTO: Codable {
    let id: UUID
    let pair1Id: UUID
    let pair2Id: UUID
    let streamChannelId: String?
    let status: String
    let matchedAt: Date
    let lastMessageAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case pair1Id = "pair1_id"
        case pair2Id = "pair2_id"
        case streamChannelId = "stream_channel_id"
        case status
        case matchedAt = "matched_at"
        case lastMessageAt = "last_message_at"
    }
}

struct SwipeDTO: Codable {
    let id: UUID
    let swiperPairId: UUID
    let swipedPairId: UUID
    let swiperUserId: UUID
    let direction: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case swiperPairId = "swiper_pair_id"
        case swipedPairId = "swiped_pair_id"
        case swiperUserId = "swiper_user_id"
        case direction
        case createdAt = "created_at"
    }
}

struct MessageDTO: Codable {
    let id: UUID
    let matchId: UUID
    let senderUserId: UUID
    let content: String
    let messageType: String
    let isRead: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case matchId = "match_id"
        case senderUserId = "sender_user_id"
        case content
        case messageType = "message_type"
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}

// MARK: - Match Errors

enum MatchError: LocalizedError {
    case swipeFailed(String)
    case checkFailed(String)
    case createFailed(String)
    case fetchFailed(String)
    case unmatchFailed(String)
    case blockFailed(String)
    case sendMessageFailed(String)
    case fetchMessagesFailed(String)
    case markReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .swipeFailed(let message):
            return "Failed to record swipe: \(message)"
        case .checkFailed(let message):
            return "Failed to check for match: \(message)"
        case .createFailed(let message):
            return "Failed to create match: \(message)"
        case .fetchFailed(let message):
            return "Failed to fetch matches: \(message)"
        case .unmatchFailed(let message):
            return "Failed to unmatch: \(message)"
        case .blockFailed(let message):
            return "Failed to block match: \(message)"
        case .sendMessageFailed(let message):
            return "Failed to send message: \(message)"
        case .fetchMessagesFailed(let message):
            return "Failed to fetch messages: \(message)"
        case .markReadFailed(let message):
            return "Failed to mark messages as read: \(message)"
        }
    }
}
