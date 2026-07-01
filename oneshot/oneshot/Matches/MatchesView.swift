import SwiftUI

struct MatchesView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""

    private var filteredMatches: [Match] {
        if searchText.isEmpty {
            return appState.matches
        }
        return appState.matches.filter { match in
            let names = [
                match.duo2?.user1?.firstName,
                match.duo2?.user2?.firstName
            ].compactMap { $0 }
            return names.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if appState.matches.isEmpty {
                    EmptyMatchesView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // New matches section
                            let newMatches = appState.matches.filter { $0.lastMessageSummary == nil }
                            if !newMatches.isEmpty {
                                NewMatchesSection(matches: newMatches)
                            }

                            // Conversations
                            let conversations = filteredMatches.filter { $0.lastMessageSummary != nil }
                            if !conversations.isEmpty {
                                ConversationsSection(matches: conversations)
                            } else if filteredMatches.isEmpty && !appState.matches.isEmpty {
                                Text("No conversations yet")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 40)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Matches")
            .searchable(text: $searchText, prompt: "Search matches")
        }
    }
}

// MARK: - New Matches Section
struct NewMatchesSection: View {
    let matches: [Match]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Matches")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(matches) { match in
                        NavigationLink(destination: ChatView(match: match)) {
                            NewMatchCard(match: match)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - New Match Card
struct NewMatchCard: View {
    let match: Match

    var body: some View {
        VStack(spacing: 8) {
            // Duo photos stacked
            ZStack {
                if let photo1 = match.duo2?.user1?.photos.first {
                    AsyncImage(url: URL(string: photo1.url)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.uchicagoMaroon.opacity(0.2))
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                    .offset(x: -15)
                }

                if let photo2 = match.duo2?.user2?.photos.first {
                    AsyncImage(url: URL(string: photo2.url)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.purple.opacity(0.2))
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .offset(x: 15)
                }
            }
            .frame(width: 100, height: 70)

            // Names
            if let user1 = match.duo2?.user1, let user2 = match.duo2?.user2 {
                Text("\(user1.firstName) & \(user2.firstName)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
        }
        .frame(width: 100)
    }
}

// MARK: - Conversations Section
struct ConversationsSection: View {
    let matches: [Match]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Messages")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 24)
                .padding(.bottom, 12)

            ForEach(matches) { match in
                NavigationLink(destination: ChatView(match: match)) {
                    ConversationRow(match: match)
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 88)
            }
        }
    }
}

// MARK: - Conversation Row
struct ConversationRow: View {
    let match: Match

    var body: some View {
        HStack(spacing: 12) {
            // Duo photos
            ZStack {
                if let photo1 = match.duo2?.user1?.photos.first {
                    AsyncImage(url: URL(string: photo1.url)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .offset(x: -10, y: -5)
                }

                if let photo2 = match.duo2?.user2?.photos.first {
                    AsyncImage(url: URL(string: photo2.url)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .offset(x: 10, y: 5)
                }
            }
            .frame(width: 64, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let user1 = match.duo2?.user1, let user2 = match.duo2?.user2 {
                        Text("\(user1.firstName) & \(user2.firstName)")
                            .font(.headline)
                    }

                    Spacer()

                    if let lastMessageAt = match.lastMessageAt {
                        Text(lastMessageAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    if let lastMessage = match.lastMessageSummary {
                        HStack(spacing: 4) {
                            Text("\(lastMessage.senderName):")
                                .foregroundStyle(.secondary)
                            Text(lastMessage.content)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .lineLimit(1)
                    }

                    Spacer()

                    if match.unreadCount > 0 {
                        Text("\(match.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.uchicagoMaroon)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

// MARK: - Empty Matches View
struct EmptyMatchesView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 60))
                .foregroundStyle(.uchicagoMaroon.gradient)

            Text("No Matches Yet")
                .font(.title2.bold())

            Text("Keep swiping to find your perfect duo match!")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            NavigationLink(destination: DiscoverView()) {
                Label("Start Swiping", systemImage: "hand.tap")
                    .padding()
                    .background(.uchicagoMaroon.gradient)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .padding()
    }
}

#Preview {
    MatchesView()
        .environmentObject(AppState())
}
