import SwiftUI
import Combine

// MARK: - View Model

/// Pending-likes tray (CLAUDE.md §7 step 5). Lists targets my partner liked that I
/// haven't; CONFIRM reuses `LikeService.like` (inserts my like_intent, which the 0004
/// trigger may promote to a duo_like / match). SKIP is a client-side dismiss only —
/// not persisted, so it reappears on relaunch (accepted MVP tradeoff).
@MainActor
final class PendingLikesViewModel: ObservableObject {
    @Published private(set) var pending: [DuoProfileDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service: PendingLikesService?
    private let likeService: LikeService?
    private let browseService: BrowseService?
    private var activeDuoId: UUID?
    private var dismissed: Set<UUID> = []   // client-side skip (not persisted — MVP)

    /// Live init.
    init(service: PendingLikesService, likeService: LikeService, browseService: BrowseService) {
        self.service = service
        self.likeService = likeService
        self.browseService = browseService
    }

    /// Sample init for previews (no network).
    init(sample: [DuoProfileDTO]) {
        self.service = nil
        self.likeService = nil
        self.browseService = nil
        self.pending = sample
    }

    /// Targets still awaiting my confirmation (skips filtered out).
    var visible: [DuoProfileDTO] { pending.filter { !dismissed.contains($0.id) } }
    var count: Int { visible.count }

    func load() async {
        guard let service, let browseService else { return } // sample VM keeps injected data
        isLoading = true
        errorMessage = nil
        do {
            activeDuoId = try await browseService.currentActiveDuoId()
            pending = try await service.pendingLikeTargets()
        } catch {
            print("❌ Pending-likes load error: \(error)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Confirm = insert MY like_intent toward the target (both-must-like §2). The row
    /// leaves the tray; the DB trigger handles duo_like / match promotion.
    func confirm(_ duo: DuoProfileDTO) async {
        guard let likeService, let from = activeDuoId else { return }
        do {
            _ = try await likeService.like(fromDuoId: from, targetDuoId: duo.id)
            pending.removeAll { $0.id == duo.id }
            // TODO(analytics): fire like_intent_sent (§10) once an analytics SDK is wired.
        } catch {
            print("❌ Confirm pending-like error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    /// Skip = dismiss for this session only (reappears on relaunch — MVP).
    func skip(_ duo: DuoProfileDTO) {
        dismissed.insert(duo.id)
    }
}

// MARK: - Tray View

struct PendingLikesView: View {
    @ObservedObject var vm: PendingLikesViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.visible.isEmpty {
                    ProgressView()
                } else if vm.visible.isEmpty {
                    PendingLikesEmptyView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(vm.visible, id: \.id) { duo in
                                PendingLikeRow(
                                    duo: duo,
                                    onConfirm: { Task { await vm.confirm(duo) } },
                                    onSkip: { vm.skip(duo) }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }
}

// MARK: - Row

struct PendingLikeRow: View {
    let duo: DuoProfileDTO
    let onConfirm: () -> Void
    let onSkip: () -> Void

    /// Storage paths resolved to signed, expiring URLs (keyed by the stored ref).
    @State private var resolvedURLs: [String: URL] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // CLAUDE.md §9 pending-tray copy (exact).
            Text("Your partner liked this duo — you in?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            photosView
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if let bio = duo.bio, !bio.isEmpty {
                Text(bio)
                    .font(.body)
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                Button(action: onSkip) {
                    Text("Skip")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(.ultraThickMaterial)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    // §9 like/confirm action.
                    Label("Confirm", systemImage: "heart.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(.uchicagoMaroon.gradient)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .task(id: duo.id) { await resolvePhotos() }
    }

    @ViewBuilder private var photosView: some View {
        let urls = Array(duo.photos.prefix(2)).compactMap { resolvedURLs[$0] }
        if urls.isEmpty {
            placeholder
        } else {
            HStack(spacing: 0) {
                ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { placeholder }
                }
            }
        }
    }

    /// Storage path → signed URL (private bucket); legacy `http` entries used as-is
    /// (TRANSITION fallback — see DuoPhotoService / Browse card).
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
                    .font(.system(size: 48))
                    .foregroundColor(.white.opacity(0.85))
            )
    }
}

// MARK: - Empty state

struct PendingLikesEmptyView: View {
    var body: some View {
        // TODO(copy): no §9 line fits an empty tray; placeholder copy for now.
        VStack(spacing: 16) {
            Image(systemName: "heart.circle")
                .font(.system(size: 60))
                .foregroundStyle(.uchicagoMaroon.gradient)
            Text("Nothing to confirm")
                .font(.title2.bold())
            Text("When your partner likes a duo, it'll show up here for you to confirm.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    PendingLikesView(vm: PendingLikesViewModel(sample: [
        DuoProfileDTO(id: UUID(), memberA: UUID(), memberB: UUID(), photos: [],
                      bio: "Astronomy club + late-night ramen. Partners in crime.",
                      activeWeek: 0, reliabilityScore: 0, status: "active", createdAt: Date())
    ]))
}
