import SwiftUI
import Combine

/// Edit the ACTIVE duo (CLAUDE.md §7 step 9, edit-duo only): bio, photos, interests.
/// Both members have equal edit rights (locked decision); RLS `duo_update_members` /
/// `duo_interest_write` / Storage `duo_photos_*` policies gate every write on
/// `is_duo_member`, so a non-member's edits are rejected server-side.
///
/// SwiftUI + MVVM. Photos reuse the shipped AppState plumbing (add/remove →
/// DuoPhotoService); bio + interests are owned by `EditDuoViewModel` (DuoEditService).
struct EditDuoView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: EditDuoViewModel
    @State private var thumbnails: [String: URL] = [:]
    @State private var showPicker = false

    init(duoId: UUID, initialBio: String) {
        _viewModel = StateObject(wrappedValue: EditDuoViewModel(duoId: duoId, initialBio: initialBio))
    }

    private var atMaxPhotos: Bool { appState.activeDuoPhotos.count >= DuoPhotoService.maxPhotos }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                bioSection
                photosSection
                interestsSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Edit Duo")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await appState.loadActiveDuoPhotos()
            await resolveThumbnails()
            await viewModel.load()
        }
        .onChange(of: appState.activeDuoPhotos) { _ in
            Task { await resolveThumbnails() }
        }
        .sheet(isPresented: $showPicker) {
            PhotoLibraryPicker { image in
                Task { await appState.addActiveDuoPhoto(image) }
            }
        }
        .alert("Something went wrong",
               isPresented: Binding(
                get: { viewModel.errorMessage != nil || appState.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil; appState.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? appState.errorMessage ?? "")
        }
    }

    // MARK: - Bio

    private var bioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Duo Bio")
                .font(.headline)

            TextEditor(text: $viewModel.bio)
                .frame(minHeight: 120)
                .padding(8)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if viewModel.bio.isEmpty {
                        Text("Tell other duos who you two are…")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                Text("\(viewModel.bio.count)/\(DuoEditService.maxBioLength)")
                    .font(.caption)
                    .foregroundStyle(viewModel.bio.count > DuoEditService.maxBioLength ? .red : .secondary)
                Spacer()
                Button {
                    Task { await viewModel.saveBio() }
                } label: {
                    if viewModel.isSavingBio {
                        ProgressView()
                    } else {
                        Text("Save Bio").font(.subheadline.bold())
                    }
                }
                .disabled(viewModel.isSavingBio)
                .foregroundColor(.uchicagoMaroon)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Photos

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Duo Photos").font(.headline)
                Spacer()
                Text("\(appState.activeDuoPhotos.count)/\(DuoPhotoService.maxPhotos)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(appState.activeDuoPhotos, id: \.self) { ref in
                        photoThumbnail(ref)
                    }

                    if !atMaxPhotos {
                        Button { showPicker = true } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.uchicagoMaroon.opacity(0.1))
                                if appState.isUploadingDuoPhoto {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus")
                                        .font(.title2)
                                        .foregroundColor(.uchicagoMaroon)
                                }
                            }
                            .frame(width: 88, height: 88)
                        }
                        .disabled(appState.isUploadingDuoPhoto)
                    }
                }
            }

            if atMaxPhotos {
                Text("You've added the max of \(DuoPhotoService.maxPhotos) photos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func photoThumbnail(_ ref: String) -> some View {
        AsyncImage(url: thumbnails[ref]) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.2))
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            Button {
                Task { await appState.removeActiveDuoPhoto(ref) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .offset(x: 6, y: -6)
            .disabled(appState.isUploadingDuoPhoto)
        }
    }

    /// Resolve each stored ref to a signed URL (legacy http seed entries used as-is).
    private func resolveThumbnails() async {
        let service = ServiceContainer.shared.duoPhotoService
        for ref in appState.activeDuoPhotos where thumbnails[ref] == nil {
            if ref.hasPrefix("http") {
                thumbnails[ref] = URL(string: ref)
            } else if let url = try? await service.signedURL(forPath: ref) {
                thumbnails[ref] = url
            }
        }
    }

    // MARK: - Interests

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interests").font(.headline)

            if viewModel.isLoadingInterests {
                ProgressView().frame(maxWidth: .infinity)
            } else if viewModel.allTags.isEmpty {
                Text("No interests available yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Tap to add or remove. Picked tags show your duo's vibe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                InterestFlow(spacing: 8) {
                    ForEach(viewModel.allTags) { tag in
                        let selected = viewModel.selectedTagIds.contains(tag.id)
                        Button {
                            Task { await viewModel.toggle(tag) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.caption)
                                Text(tag.label).font(.subheadline)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selected ? Color.uchicagoMaroon : Color(.tertiarySystemBackground))
                            .foregroundColor(selected ? .white : .primary)
                            .clipShape(Capsule())
                        }
                        .disabled(viewModel.busyTagIds.contains(tag.id))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - View Model

@MainActor
final class EditDuoViewModel: ObservableObject {
    @Published var bio: String
    @Published var allTags: [InterestTagDTO] = []
    @Published var selectedTagIds: Set<UUID> = []
    @Published var busyTagIds: Set<UUID> = []
    @Published var isLoadingInterests = false
    @Published var isSavingBio = false
    @Published var errorMessage: String?

    private let duoId: UUID
    private let service = ServiceContainer.shared.duoEditService

    init(duoId: UUID, initialBio: String) {
        self.duoId = duoId
        self.bio = initialBio
    }

    func load() async {
        isLoadingInterests = true
        defer { isLoadingInterests = false }
        do {
            async let tags = service.allTags()
            async let mine = service.interestTagIds(forDuo: duoId)
            allTags = try await tags
            selectedTagIds = try await mine
        } catch {
            print("❌ Load interests error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    func saveBio() async {
        isSavingBio = true
        defer { isSavingBio = false }
        do {
            try await service.updateBio(duoId: duoId, bio: bio)
            // TODO(analytics): §10 has no duo_edited event — nothing to fire here.
            print("✅ Duo bio saved")
        } catch {
            print("❌ Save bio error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    /// Optimistically toggle a tag; revert on failure.
    func toggle(_ tag: InterestTagDTO) async {
        guard !busyTagIds.contains(tag.id) else { return }
        busyTagIds.insert(tag.id)
        defer { busyTagIds.remove(tag.id) }

        let wasSelected = selectedTagIds.contains(tag.id)
        if wasSelected { selectedTagIds.remove(tag.id) } else { selectedTagIds.insert(tag.id) }

        do {
            if wasSelected {
                try await service.removeInterest(duoId: duoId, tagId: tag.id)
            } else {
                try await service.addInterest(duoId: duoId, tagId: tag.id)
            }
        } catch {
            // Revert the optimistic change.
            if wasSelected { selectedTagIds.insert(tag.id) } else { selectedTagIds.remove(tag.id) }
            print("❌ Toggle interest error: \(error)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Simple wrapping flow layout for interest chips

/// Minimal flow layout (wraps chips onto multiple lines). Uses SwiftUI's `Layout`
/// (iOS 16+, matches the project target).
struct InterestFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGFloat]] = [[]]
        var x: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                totalHeight += rowHeight + spacing
                rows.append([])
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
