import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentIndex = 0
    @State private var showMatchAlert = false
    @State private var matchedDuo: Duo?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if appState.currentDuo == nil {
                    NoDuoPromptView()
                } else if appState.discoveryDuos.isEmpty {
                    EmptyDiscoveryView()
                } else {
                    CardStackView(
                        duos: appState.discoveryDuos,
                        onSwipe: handleSwipe
                    )
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(.uchicagoMaroon.gradient)
                }
            }
            .alert("It's a Match!", isPresented: $showMatchAlert) {
                Button("Send a Message") {
                    // Navigate to chat
                }
                Button("Keep Swiping", role: .cancel) {}
            } message: {
                if let duo = matchedDuo {
                    Text("You and \(duo.user1?.firstName ?? "") & \(duo.user2?.firstName ?? "") liked each other!")
                }
            }
        }
    }

    private func handleSwipe(_ action: SwipeAction, duo: Duo) {
        Task {
            let previousMatchCount = appState.matches.count
            await appState.swipe(action, on: duo)

            // Check if we got a new match
            if appState.matches.count > previousMatchCount {
                matchedDuo = duo
                showMatchAlert = true
            }
        }
    }
}

// MARK: - Card Stack View
struct CardStackView: View {
    let duos: [Duo]
    let onSwipe: (SwipeAction, Duo) -> Void

    @State private var offsets: [UUID: CGSize] = [:]
    @State private var activeIndex = 0

    var body: some View {
        ZStack {
            ForEach(Array(duos.prefix(3).enumerated().reversed()), id: \.element.id) { index, duo in
                DuoCard(duo: duo, isTop: index == 0)
                    .offset(offsets[duo.id] ?? .zero)
                    .rotationEffect(.degrees(Double((offsets[duo.id]?.width ?? 0) / 20)))
                    .scaleEffect(index == 0 ? 1 : 1 - CGFloat(index) * 0.05)
                    .offset(y: CGFloat(index) * 8)
                    .gesture(
                        index == 0 ? DragGesture()
                            .onChanged { value in
                                offsets[duo.id] = value.translation
                            }
                            .onEnded { value in
                                handleDragEnd(value: value, duo: duo)
                            }
                        : nil
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: offsets[duo.id])
            }

            // Action buttons
            VStack {
                Spacer()
                ActionButtonsView { action in
                    if let duo = duos.first {
                        performSwipe(action, on: duo)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .padding()
    }

    private func handleDragEnd(value: DragGesture.Value, duo: Duo) {
        let threshold: CGFloat = 100

        if value.translation.width > threshold {
            performSwipe(.like, on: duo)
        } else if value.translation.width < -threshold {
            performSwipe(.pass, on: duo)
        } else {
            offsets[duo.id] = .zero
        }
    }

    private func performSwipe(_ action: SwipeAction, on duo: Duo) {
        withAnimation(.easeOut(duration: 0.3)) {
            offsets[duo.id] = CGSize(
                width: action == .like ? 500 : -500,
                height: 0
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onSwipe(action, duo)
            offsets.removeValue(forKey: duo.id)
        }
    }
}

// MARK: - Duo Card
struct DuoCard: View {
    let duo: Duo
    let isTop: Bool

    @State private var currentPhotoIndex = 0
    @State private var showingUser1 = true

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Photos
                TabView(selection: $currentPhotoIndex) {
                    // Both users side by side
                    HStack(spacing: 0) {
                        if let user1 = duo.user1 {
                            UserPhotoView(user: user1, showInfo: true)
                        }
                        if let user2 = duo.user2 {
                            UserPhotoView(user: user2, showInfo: true)
                        }
                    }
                    .tag(0)

                    // Individual photos carousel
                    if let user1 = duo.user1 {
                        ForEach(Array(user1.photos.enumerated()), id: \.element.id) { index, photo in
                            AsyncImage(url: URL(string: photo.url)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .overlay {
                                        ProgressView()
                                    }
                            }
                            .tag(index + 1)
                        }
                    }

                    if let user2 = duo.user2 {
                        ForEach(Array(user2.photos.enumerated()), id: \.element.id) { index, photo in
                            AsyncImage(url: URL(string: photo.url)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                            }
                            .tag((duo.user1?.photos.count ?? 0) + index + 1)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(width: geometry.size.width, height: geometry.size.height)

                // Info overlay
                VStack(alignment: .leading, spacing: 8) {
                    // Names and ages
                    HStack {
                        if let user1 = duo.user1, let user2 = duo.user2 {
                            Text("\(user1.firstName), \(user1.age) & \(user2.firstName), \(user2.age)")
                                .font(.title2.bold())
                                .foregroundColor(.white)
                        }
                        Spacer()
                        NavigationLink(destination: DuoProfileView(duo: duo)) {
                            Image(systemName: "info.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }

                    // University
                    if let uni = duo.user1?.university ?? duo.user2?.university {
                        Label(uni, systemImage: "building.columns")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }

                    // Duo bio
                    if !duo.duoBio.isEmpty {
                        Text(duo.duoBio)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                    }

                    // Shared interests
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(duo.combinedInterests.prefix(5)) { interest in
                                Text("\(interest.emoji) \(interest.name)")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(20)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        }
    }
}

// MARK: - User Photo View
struct UserPhotoView: View {
    let user: UserSummary
    let showInfo: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                if let photo = user.photos.first {
                    AsyncImage(url: URL(string: photo.url)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.uchicagoMaroon.opacity(0.3), .purple.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay {
                                Text(user.firstName.prefix(1))
                                    .font(.system(size: 60, weight: .bold))
                                    .foregroundColor(.white)
                            }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                }

                if showInfo {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.firstName)
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("\(user.age)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(12)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
    }
}

// MARK: - Action Buttons
struct ActionButtonsView: View {
    let onAction: (SwipeAction) -> Void

    var body: some View {
        HStack(spacing: 24) {
            // Pass button
            ActionButton(
                icon: "xmark",
                color: .gray,
                size: 60
            ) {
                onAction(.pass)
            }

            // Super Like button
            ActionButton(
                icon: "star.fill",
                color: .blue,
                size: 50
            ) {
                onAction(.superLike)
            }

            // Like button
            ActionButton(
                icon: "heart.fill",
                color: .uchicagoMaroon,
                size: 60
            ) {
                onAction(.like)
            }
        }
    }
}

struct ActionButton: View {
    let icon: String
    let color: Color
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(color)
                .frame(width: size, height: size)
                .background(.ultraThickMaterial)
                .clipShape(Circle())
                .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - Empty State
struct EmptyDiscoveryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundStyle(.uchicagoMaroon.gradient)

            Text("No More Duos")
                .font(.title2.bold())

            Text("You've seen everyone nearby!\nCheck back later or expand your preferences.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                // Refresh or go to settings
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .padding()
                    .background(.uchicagoMaroon.opacity(0.1))
                    .foregroundColor(.uchicagoMaroon)
                    .clipShape(Capsule())
            }
        }
        .padding()
    }
}

// MARK: - No Duo Prompt
struct NoDuoPromptView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Duo Yet")
                .font(.title2.bold())

            Text("You need a duo partner to start swiping.\nTeam up with a friend first!")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            NavigationLink(destination: DuoManagementView()) {
                Label("Find Your Duo", systemImage: "person.badge.plus")
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
    DiscoverView()
        .environmentObject(AppState())
}
