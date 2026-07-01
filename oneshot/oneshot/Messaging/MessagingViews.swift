import SwiftUI
import Combine
import Supabase
import Realtime

// MARK: - Matches list

@MainActor
final class MatchListViewModel: ObservableObject {
    @Published var matches: [DuoMatchDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let matchService: MatchService
    init(matchService: MatchService) { self.matchService = matchService }

    func load() async {
        isLoading = true
        errorMessage = nil
        do { matches = try await matchService.fetchActiveMatches() }
        catch {
            print("❌ Matches load error: \(error)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct MatchListView: View {
    @StateObject private var vm = MatchListViewModel(matchService: ServiceContainer.shared.matchService)

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView()
                } else if vm.matches.isEmpty {
                    BrowseMessageView(systemImage: "heart.slash",
                                      title: "No matches yet",
                                      subtitle: "When two duos like each other, they'll show up here.")
                } else {
                    List(vm.matches) { match in
                        NavigationLink {
                            MatchChatView(matchId: match.id)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "person.2.fill")
                                    .foregroundStyle(.uchicagoMaroon.gradient)
                                    .frame(width: 40, height: 40)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    // CLAUDE.md §9 match copy
                                    Text("You matched — say hi?").font(.headline)
                                    Text("Tap to open the chat")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Matches")
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }
}

// MARK: - Chat (live via Realtime)

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessageDTO] = []
    @Published var draft = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    let matchId: UUID
    let myUserId: UUID?
    private let service: ChatService
    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?

    init(matchId: UUID, service: ChatService, myUserId: UUID?) {
        self.matchId = matchId
        self.service = service
        self.myUserId = myUserId
    }

    func isMine(_ m: ChatMessageDTO) -> Bool { m.senderUserId == myUserId }

    /// Load history, then subscribe to live inserts (§8).
    func start() async {
        isLoading = true
        do { messages = try await service.loadMessages(matchId: matchId) }
        catch {
            print("❌ Chat load error: \(error)")
            errorMessage = error.localizedDescription
        }
        isLoading = false

        let ch = service.channel(matchId: matchId)
        channel = ch
        // Register the postgres-change listener BEFORE subscribing.
        let stream = service.messageInserts(on: ch, matchId: matchId)
        listenTask = Task { [weak self] in
            for await msg in stream {
                guard let self else { continue }
                if !self.messages.contains(where: { $0.id == msg.id }) {
                    self.messages.append(msg)
                }
            }
        }
        await ch.subscribe()
    }

    func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        draft = ""
        do {
            let msg = try await service.sendMessage(matchId: matchId, body: body)
            // Realtime will also deliver our own insert; dedup by id.
            if !messages.contains(where: { $0.id == msg.id }) { messages.append(msg) }
        } catch {
            print("❌ Send message error: \(error)")
            errorMessage = error.localizedDescription
            draft = body
        }
    }

    /// Unsubscribe on view disappear (§8).
    func stop() async {
        listenTask?.cancel()
        listenTask = nil
        if let channel {
            await channel.unsubscribe()
            self.channel = nil
        }
    }
}

struct MatchChatView: View {
    @StateObject private var vm: ChatViewModel

    init(matchId: UUID) {
        _vm = StateObject(wrappedValue: ChatViewModel(
            matchId: matchId,
            service: ServiceContainer.shared.chatService,
            myUserId: ServiceContainer.shared.authService.currentUserId
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.messages) { msg in
                            ChatMessageBubble(text: msg.body, isMine: vm.isMine(msg))
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: vm.messages.count) { _ in
                    if let last = vm.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                TextField("Message", text: $vm.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    Task { await vm.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.uchicagoMaroon.gradient)
                }
                .disabled(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.start() }
        .onDisappear { Task { await vm.stop() } }
    }
}

struct ChatMessageBubble: View {
    let text: String
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 40) }
            Text(text)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(isMine ? Color.uchicagoMaroon : Color(.secondarySystemBackground))
                .foregroundColor(isMine ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if !isMine { Spacer(minLength: 40) }
        }
    }
}
