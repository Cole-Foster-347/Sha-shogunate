import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    let match: Match
    @State private var messageText = ""
    @State private var messages: [Message] = []
    @State private var showIcebreakers = false
    @State private var showDateSuggestion = false
    @FocusState private var isInputFocused: Bool

    private var otherDuo: Duo? {
        guard let currentDuoId = appState.currentDuo?.id else { return match.duo2 }
        return match.duo1Id == currentDuoId ? match.duo2 : match.duo1
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Match header
                        MatchHeaderView(duo: otherDuo)
                            .padding(.top, 20)
                            .padding(.bottom, 10)

                        // Messages
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                isFromCurrentUser: message.senderId == appState.currentUser?.id
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Icebreaker suggestions & Input
            if messages.isEmpty {
                IcebreakerSuggestions { icebreaker in
                    sendMessage(icebreaker, type: .icebreaker)
                }

                ForcedIcebreakerView {
                    showIcebreakers = true
                }
            } else {
                // Input bar
                ChatInputBar(
                    text: $messageText,
                    isFocused: $isInputFocused,
                    onSend: {
                        sendMessage(messageText)
                        messageText = ""
                    },
                    onIcebreaker: { showIcebreakers = true },
                    onDateSuggestion: { showDateSuggestion = true }
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ChatNavigationTitle(duo: otherDuo)
            }

            ToolbarItem(placement: .topBarTrailing) {
                if let duo = otherDuo {
                    NavigationLink(destination: DuoProfileView(duo: duo)) {
                        Image(systemName: "info.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showIcebreakers) {
            IcebreakerPickerView { icebreaker in
                sendMessage(icebreaker, type: .icebreaker)
                showIcebreakers = false
            }
        }
        .sheet(isPresented: $showDateSuggestion) {
            DateSuggestionView { suggestion in
                sendMessage(suggestion, type: .dateSuggestion)
                showDateSuggestion = false
            }
        }
        .onAppear {
            loadMessages()
        }
    }

    private func sendMessage(_ content: String, type: MessageType = .text) {
        guard let currentUser = appState.currentUser else { return }

        let message = Message(
            id: UUID(),
            matchId: match.id,
            senderId: currentUser.id,
            senderSummary: UserSummary(from: currentUser),
            content: content,
            messageType: type,
            createdAt: Date(),
            isRead: false
        )

        messages.append(message)
        Task {
            await appState.sendMessage(to: match.id, content: content, type: type)
        }
    }

    private func loadMessages() {
        Task {
            let fetchedMessages = await appState.fetchMessages(matchId: match.id)
            messages = fetchedMessages
        }
    }
}

// MARK: - Chat Navigation Title
struct ChatNavigationTitle: View {
    let duo: Duo?

    var body: some View {
        HStack(spacing: 8) {
            // Mini duo photos
            ZStack {
                if let photo1 = duo?.user1?.photos.first {
                    AsyncImage(url: URL(string: photo1.url)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                    .offset(x: -6)
                }

                if let photo2 = duo?.user2?.photos.first {
                    AsyncImage(url: URL(string: photo2.url)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1))
                    .offset(x: 6)
                }
            }
            .frame(width: 44)

            if let user1 = duo?.user1, let user2 = duo?.user2 {
                Text("\(user1.firstName) & \(user2.firstName)")
                    .font(.headline)
            }
        }
    }
}

// MARK: - Match Header View
struct MatchHeaderView: View {
    let duo: Duo?

    var body: some View {
        VStack(spacing: 12) {
            // Duo photos
            ZStack {
                if let photo1 = duo?.user1?.photos.first {
                    AsyncImage(url: URL(string: photo1.url)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.uchicagoMaroon.opacity(0.2))
                    }
                    .frame(width: 70, height: 70)
                    .clipShape(Circle())
                    .offset(x: -20)
                }

                if let photo2 = duo?.user2?.photos.first {
                    AsyncImage(url: URL(string: photo2.url)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.purple.opacity(0.2))
                    }
                    .frame(width: 70, height: 70)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .offset(x: 20)
                }
            }

            VStack(spacing: 4) {
                if let user1 = duo?.user1, let user2 = duo?.user2 {
                    Text("You matched with \(user1.firstName) & \(user2.firstName)!")
                        .font(.headline)
                }

                Text("Start a conversation!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: Message
    let isFromCurrentUser: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isFromCurrentUser {
                Spacer(minLength: 60)
            } else {
                // Avatar
                if let photo = message.senderSummary?.photos.first {
                    AsyncImage(url: URL(string: photo.url)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                }
            }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Sender name (for others)
                if !isFromCurrentUser, let sender = message.senderSummary {
                    Text(sender.firstName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Message content
                Group {
                    switch message.messageType {
                    case .text:
                        Text(message.content)

                    case .icebreaker:
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Icebreaker", systemImage: "snowflake")
                                .font(.caption2)
                                .foregroundStyle(isFromCurrentUser ? .white.opacity(0.8) : .uchicagoMaroon)
                            Text(message.content)
                        }

                    case .dateSuggestion:
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Date Suggestion", systemImage: "calendar.badge.plus")
                                .font(.caption2)
                                .foregroundStyle(isFromCurrentUser ? .white.opacity(0.8) : .uchicagoMaroon)
                            Text(message.content)
                        }

                    case .image:
                        Text(message.content)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isFromCurrentUser ? Color.uchicagoMaroon : Color(.secondarySystemBackground))
                .foregroundColor(isFromCurrentUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                // Timestamp
                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !isFromCurrentUser {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Chat Input Bar
struct ChatInputBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onIcebreaker: () -> Void
    let onDateSuggestion: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                // Extras menu
                Menu {
                    Button {
                        onIcebreaker()
                    } label: {
                        Label("Icebreaker", systemImage: "snowflake")
                    }

                    Button {
                        onDateSuggestion()
                    } label: {
                        Label("Suggest a Date", systemImage: "calendar.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.uchicagoMaroon)
                }

                // Text field
                TextField("Message...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .lineLimit(1...4)
                    .focused(isFocused)

                // Send button
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(.uchicagoMaroon)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - Icebreaker Suggestions
struct IcebreakerSuggestions: View {
    let onSelect: (String) -> Void

    private let suggestions = [
        "What's your favorite double date activity?",
        "If we all won a trip together, where should we go?",
        "What's the most spontaneous thing you've done as a duo?"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Icebreakers")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            onSelect(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.uchicagoMaroon.opacity(0.1))
                                .foregroundColor(.uchicagoMaroon)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Icebreaker Picker View
struct IcebreakerPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) -> Void

    private let icebreakers = [
        "What's the best double date you've ever been on?",
        "If you could plan our first double date, what would it be?",
        "What's something fun we could all do together?",
        "What's your duo's favorite thing to do together?",
        "If we all went on a road trip, where should we go?",
        "What's the most adventurous thing you've done as a duo?",
        "What's your go-to karaoke song as a duo?",
        "If we had a game night, what game would you choose?"
    ]

    var body: some View {
        NavigationStack {
            List(icebreakers, id: \.self) { icebreaker in
                Button {
                    onSelect(icebreaker)
                } label: {
                    Text(icebreaker)
                        .foregroundColor(.primary)
                }
            }
            .navigationTitle("Icebreakers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Date Suggestion View
struct DateSuggestionView: View {
    @Environment(\.dismiss) private var dismiss
    let onSend: (String) -> Void

    @State private var selectedType: DateType = .activity
    @State private var customSuggestion = ""
    @State private var selectedDate = Date()

    enum DateType: String, CaseIterable {
        case activity = "Activity"
        case food = "Food & Drinks"
        case adventure = "Adventure"
        case chill = "Chill"
    }

    private let suggestions: [DateType: [String]] = [
        .activity: ["Bowling night", "Mini golf", "Escape room", "Karaoke"],
        .food: ["Brunch", "Wine tasting", "Cooking class", "Food tour"],
        .adventure: ["Hiking", "Beach day", "Road trip", "Camping"],
        .chill: ["Game night", "Movie marathon", "Picnic in the park", "Coffee shop hopping"]
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Type picker
                Picker("Type", selection: $selectedType) {
                    ForEach(DateType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Suggestions
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(suggestions[selectedType] ?? [], id: \.self) { suggestion in
                            Button {
                                onSend("How about \(suggestion.lowercased())?")
                            } label: {
                                Text(suggestion)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                // Custom suggestion
                VStack(alignment: .leading, spacing: 8) {
                    Text("Or suggest your own")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("Your idea...", text: $customSuggestion)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            if !customSuggestion.isEmpty {
                                onSend("How about \(customSuggestion)?")
                            }
                        } label: {
                            Text("Send")
                                .fontWeight(.medium)
                        }
                        .disabled(customSuggestion.isEmpty)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("Suggest a Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Forced Icebreaker View
struct ForcedIcebreakerView: View {
    let onOpenPicker: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Divider()

            VStack(spacing: 8) {
                Text("Start the conversation")
                    .font(.headline)

                Text("Pick an icebreaker to say hello!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            Button(action: onOpenPicker) {
                Label("Choose Icebreaker", systemImage: "snowflake")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.uchicagoMaroon.gradient)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }
}

#Preview {
    let appState = AppState()
    let mockMatch = Match(
        id: UUID(),
        duo1Id: UUID(),
        duo2Id: UUID(),
        duo1: nil,
        duo2: appState.discoveryDuos.first,
        createdAt: Date(),
        lastMessageAt: nil,
        lastMessageSummary: nil,
        unreadCount: 0
    )

    return NavigationStack {
        ChatView(match: mockMatch)
            .environmentObject(appState)
    }
}