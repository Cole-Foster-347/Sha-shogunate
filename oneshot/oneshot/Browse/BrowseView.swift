import SwiftUI
import Combine

// MARK: - View Model

@MainActor
final class BrowseViewModel: ObservableObject {
    @Published var duos: [DuoProfileDTO] = []
    @Published var currentIndex = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var likedTargets: Set<UUID> = []

    private let service: BrowseService?
    private let likeService: LikeService?
    private var activeDuoId: UUID?

    /// Live init — fetches from the canonical backend.
    init(service: BrowseService, likeService: LikeService) {
        self.service = service
        self.likeService = likeService
    }

    /// Sample init for SwiftUI previews / harnesses (no network).
    init(sampleDuos: [DuoProfileDTO]) {
        self.service = nil
        self.likeService = nil
        self.duos = sampleDuos
    }

    var isExhausted: Bool { currentIndex >= duos.count }

    var currentDuo: DuoProfileDTO? {
        currentIndex < duos.count ? duos[currentIndex] : nil
    }

    /// Up to 3 cards from the current index, nearest first.
    var visibleCards: [(depth: Int, duo: DuoProfileDTO)] {
        guard currentIndex < duos.count else { return [] }
        let end = min(currentIndex + 3, duos.count)
        return (currentIndex..<end).map { (depth: $0 - currentIndex, duo: duos[$0]) }
    }

    func load() async {
        guard let service else { return } // sample VM: keep injected duos
        isLoading = true
        errorMessage = nil
        do {
            activeDuoId = try await service.currentActiveDuoId()
            duos = try await service.fetchBrowseableDuos()
            currentIndex = 0
            // TODO(analytics): fire profile_view (§10) for the first shown card once an
            // analytics SDK is wired (none is integrated yet).
        } catch {
            print("❌ Browse load error: \(error)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Like the top card: insert ONE like_intent for the current user, then advance.
    /// The DB triggers handle promotion to duo_like / match (we don't here).
    func like(_ duo: DuoProfileDTO) async {
        defer { advance() }
        guard let likeService, let from = activeDuoId else { return }
        do {
            _ = try await likeService.like(fromDuoId: from, targetDuoId: duo.id)
            likedTargets.insert(duo.id) // dup taps are a no-op (23505 handled in the service)
        } catch {
            print("❌ Like error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    /// Advance past the top card (a pass — no write).
    func advance() {
        guard currentIndex < duos.count else { return }
        currentIndex += 1
        // TODO(analytics): fire profile_view (§10) for the newly shown card.
    }
}

// MARK: - Browse View

struct BrowseView: View {
    @StateObject private var vm: BrowseViewModel

    /// Defaults to the live service; inject a sample VM for previews/harnesses.
    init(viewModel: BrowseViewModel? = nil) {
        _vm = StateObject(wrappedValue: viewModel
            ?? BrowseViewModel(service: ServiceContainer.shared.browseService,
                               likeService: ServiceContainer.shared.likeService))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if vm.isLoading {
                    ProgressView()
                } else if let msg = vm.errorMessage, vm.duos.isEmpty {
                    BrowseMessageView(systemImage: "exclamationmark.triangle",
                                      title: "Couldn't load duos", subtitle: msg)
                } else if vm.isExhausted {
                    BrowseEmptyView()
                } else {
                    BrowseCardStack(vm: vm)
                }
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "person.2.fill").foregroundStyle(.uchicagoMaroon.gradient)
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }
}

// MARK: - Card Stack

struct BrowseCardStack: View {
    @ObservedObject var vm: BrowseViewModel
    @State private var topOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                ForEach(vm.visibleCards.reversed(), id: \.duo.id) { item in
                    BrowseDuoCard(duo: item.duo)
                        .scaleEffect(item.depth == 0 ? 1 : 1 - CGFloat(item.depth) * 0.04)
                        .offset(y: CGFloat(item.depth) * 10)
                        .offset(item.depth == 0 ? topOffset : .zero)
                        .rotationEffect(.degrees(item.depth == 0 ? Double(topOffset.width / 20) : 0))
                        .gesture(item.depth == 0 ? dragGesture : nil)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: topOffset)
                        .animation(.easeInOut, value: vm.currentIndex)
                }
            }

            // Pass / Like actions. A drag also just advances (pass) for now.
            HStack(spacing: 40) {
                Button {
                    vm.advance()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.gray)
                        .frame(width: 64, height: 64)
                        .background(.ultraThickMaterial).clipShape(Circle())
                }

                Button {
                    if let duo = vm.currentDuo { Task { await vm.like(duo) } }
                } label: {
                    // CLAUDE.md §9 copy: "Like"
                    Label("Like", systemImage: "heart.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 28).frame(height: 64)
                        .background(.uchicagoMaroon.gradient).clipShape(Capsule())
                }
            }
        }
        .padding()
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { topOffset = $0.translation }
            .onEnded { value in
                let threshold: CGFloat = 100
                if abs(value.translation.width) > threshold {
                    // Fling the card off, then advance (no like action yet).
                    withAnimation(.easeOut(duration: 0.25)) {
                        topOffset = CGSize(width: value.translation.width > 0 ? 600 : -600,
                                           height: value.translation.height)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        vm.advance()
                        topOffset = .zero
                    }
                } else {
                    withAnimation { topOffset = .zero }
                }
            }
    }
}

// MARK: - Duo Card

struct BrowseDuoCard: View {
    let duo: DuoProfileDTO

    /// Storage paths resolved to signed, expiring URLs (keyed by the stored ref).
    @State private var resolvedURLs: [String: URL] = [:]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                photosView

                LinearGradient(colors: [.clear, .black.opacity(0.65)],
                               startPoint: .center, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 10) {
                    // CLAUDE.md §9 browse line
                    Text("IRL > DMs")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())

                    if let bio = duo.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(3)
                    }
                }
                .padding(20)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        }
        .onAppear {
            // TODO(analytics): fire profile_view (§10) for this duo once analytics exists.
        }
        .task(id: duo.id) {
            await resolvePhotos()
        }
    }

    /// Duo photos — shown side-by-side (one per member) to read as a pair.
    /// Entries in `photos[]` are Storage PATHS resolved to signed, expiring URLs
    /// (CLAUDE.md §4). TRANSITION: legacy seed rows hold public `http` URLs; those
    /// are used as-is (see `photoURL(for:)`).
    @ViewBuilder private var photosView: some View {
        let refs = Array(duo.photos.prefix(2))
        let urls = refs.compactMap { resolvedURLs[$0] }
        if urls.isEmpty {
            placeholder
        } else {
            HStack(spacing: 0) {
                ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        placeholder
                    }
                }
            }
        }
    }

    /// Resolve stored photo refs to loadable URLs when the card appears.
    /// - Storage path  → signed, expiring URL via DuoPhotoService (private bucket).
    /// - `http` URL    → used as-is (TRANSITION fallback for legacy seed data).
    /// TODO(§4): drop the `http` branch once seed duos carry real uploaded paths.
    private func resolvePhotos() async {
        let service = ServiceContainer.shared.duoPhotoService
        for ref in duo.photos.prefix(2) where resolvedURLs[ref] == nil {
            if ref.hasPrefix("http") {
                resolvedURLs[ref] = URL(string: ref)
            } else if let url = try? await service.signedURL(forPath: ref) {
                resolvedURLs[ref] = url
            }
        }
    }

    private var placeholder: some View {
        LinearGradient(colors: [.uchicagoMaroon.opacity(0.75), .uchicagoMaroonLight.opacity(0.75)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(
                Image(systemName: "person.2.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.white.opacity(0.85))
            )
    }
}

// MARK: - Empty / message states

struct BrowseEmptyView: View {
    var body: some View {
        // TODO(copy): no §9 line fits an empty browse stack; placeholder copy for now.
        BrowseMessageView(systemImage: "checkmark.circle",
                          title: "You're all caught up",
                          subtitle: "No more duos to show right now. Check back soon.")
    }
}

struct BrowseMessageView: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 60))
                .foregroundStyle(.uchicagoMaroon.gradient)
            Text(title).font(.title2.bold())
            Text(subtitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    BrowseView(viewModel: BrowseViewModel(sampleDuos: [
        DuoProfileDTO(id: UUID(), memberA: UUID(), memberB: UUID(), photos: [],
                      bio: "Coffee snobs who will out-talk your group chat.",
                      activeWeek: 0, reliabilityScore: 0, status: "active", createdAt: Date()),
        DuoProfileDTO(id: UUID(), memberA: UUID(), memberB: UUID(), photos: [],
                      bio: "Hiking, board games, and questionable karaoke.",
                      activeWeek: 0, reliabilityScore: 0, status: "active", createdAt: Date())
    ]))
}
