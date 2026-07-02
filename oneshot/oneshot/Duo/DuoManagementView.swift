import SwiftUI

struct DuoManagementView: View {
    @EnvironmentObject var appState: AppState
    @State private var showInviteSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let duo = appState.currentDuo {
                        // Has a duo - show duo info
                        CurrentDuoSection(duo: duo)
                    } else {
                        // No duo - show options
                        NoDuoSection(
                            pendingInvites: appState.pendingInvites,
                            showInviteSheet: $showInviteSheet,
                            onAcceptInvite: { invite in
                                Task { await appState.acceptInvite(invite) }
                            },
                            onDeclineInvite: { invite in
                                Task { await appState.declineInvite(invite) }
                            }
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Your Duo")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showInviteSheet) {
                InviteFriendView()
            }
        }
    }
}

// MARK: - Current Duo Section
struct CurrentDuoSection: View {
    @EnvironmentObject var appState: AppState
    let duo: Duo
    @State private var showLeaveAlert = false

    var body: some View {
        VStack(spacing: 24) {
            // Duo Partner Card
            VStack(spacing: 16) {
                Text("Your Duo Partner")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let partner = duo.user1?.id == appState.currentUser?.id ? duo.user2 : duo.user1 {
                    DuoPartnerCard(user: partner)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // Duo photos (canonical duo_profile.photos[] — private bucket, signed URLs)
            DuoPhotosSection()

            // Duo Profile Preview
            NavigationLink(destination: DuoPreviewView(duo: duo)) {
                HStack {
                    Image(systemName: "eye.fill")
                        .foregroundColor(.uchicagoMaroon)

                    VStack(alignment: .leading) {
                        Text("Preview Duo Profile")
                            .font(.headline)
                        Text("See how others view your duo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            // Edit Duo Bio
            NavigationLink(destination: EditDuoBioView(duo: duo)) {
                HStack {
                    Image(systemName: "pencil")
                        .foregroundColor(.uchicagoMaroon)

                    VStack(alignment: .leading) {
                        Text("Edit Duo Bio")
                            .font(.headline)
                        Text("Customize your duo's profile")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            // Leave Duo
            Button {
                showLeaveAlert = true
            } label: {
                HStack {
                    Image(systemName: "person.badge.minus")
                        .foregroundColor(.red)

                    Text("Leave Duo")
                        .foregroundColor(.red)

                    Spacer()
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .alert("Leave Duo?", isPresented: $showLeaveAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Leave", role: .destructive) {
                    Task { await appState.leaveDuo() }
                }
            } message: {
                Text("Are you sure you want to leave your duo? You won't be able to swipe until you join another duo.")
            }
        }
    }
}

// MARK: - Duo Photos Section
/// Add-only duo photos for the ACTIVE duo. Uploads go to the private `duo-photos`
/// bucket as Storage PATHS on `duo_profile.photos[]`; thumbnails load via signed,
/// expiring URLs (CLAUDE.md §4). Reorder/delete UI is out of scope for this ticket.
struct DuoPhotosSection: View {
    @EnvironmentObject var appState: AppState
    @State private var showPicker = false
    @State private var thumbnails: [String: URL] = [:]

    private var atMax: Bool { appState.activeDuoPhotos.count >= DuoPhotoService.maxPhotos }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Duo Photos")
                    .font(.headline)
                Spacer()
                Text("\(appState.activeDuoPhotos.count)/\(DuoPhotoService.maxPhotos)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(appState.activeDuoPhotos, id: \.self) { ref in
                        thumbnail(for: ref)
                    }

                    if !atMax {
                        Button {
                            showPicker = true
                        } label: {
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

            if atMax {
                Text("You've added the max of \(DuoPhotoService.maxPhotos) photos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await appState.loadActiveDuoPhotos()
            await resolveThumbnails()
        }
        .onChange(of: appState.activeDuoPhotos) { _ in
            Task { await resolveThumbnails() }
        }
        .sheet(isPresented: $showPicker) {
            PhotoLibraryPicker { image in
                Task { await appState.addActiveDuoPhoto(image) }
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for ref: String) -> some View {
        AsyncImage(url: thumbnails[ref]) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Resolve each stored ref to a signed URL (or use legacy http entries as-is).
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
}

// MARK: - Duo Partner Card
struct DuoPartnerCard: View {
    let user: UserSummary

    var body: some View {
        HStack(spacing: 16) {
            // Photo
            if let photo = user.photos.first {
                AsyncImage(url: URL(string: photo.url)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.uchicagoMaroon.opacity(0.2))
                        .overlay {
                            Text(user.firstName.prefix(1))
                                .font(.title)
                                .foregroundColor(.uchicagoMaroon)
                        }
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(user.firstName)
                    .font(.title3.bold())

                Text("\(user.age) years old")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let university = user.university {
                    Text(university)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }
}

// MARK: - No Duo Section
struct NoDuoSection: View {
    let pendingInvites: [DuoInvite]
    @Binding var showInviteSheet: Bool
    let onAcceptInvite: (DuoInvite) -> Void
    let onDeclineInvite: (DuoInvite) -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Invite button
            Button {
                showInviteSheet = true
            } label: {
                HStack {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)

                    VStack(alignment: .leading) {
                        Text("Invite a Friend")
                            .font(.headline)
                        Text("Send an invite to form a duo")
                            .font(.caption)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                }
                .padding()
                .foregroundColor(.white)
                .background(.uchicagoMaroon.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            // Pending invites
            if !pendingInvites.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Duo Invites")
                        .font(.headline)

                    ForEach(pendingInvites) { invite in
                        InviteCard(
                            invite: invite,
                            onAccept: { onAcceptInvite(invite) },
                            onDecline: { onDeclineInvite(invite) }
                        )
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            // Explainer
            VStack(spacing: 16) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.uchicagoMaroon.gradient)

                Text("Why a Duo?")
                    .font(.headline)

                Text("Dating with a friend makes everything more fun! Match with other duos and go on amazing double dates together.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Invite Card
struct InviteCard: View {
    let invite: DuoInvite
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Profile image
            if let user = invite.fromUser, let photo = user.photos.first {
                AsyncImage(url: URL(string: photo.url)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(invite.fromUser?.firstName ?? "Someone")
                    .font(.headline)

                Text("wants to be your duo!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onDecline) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Circle())
                }

                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(.uchicagoMaroon)
                        .clipShape(Circle())
                }
            }
        }
        .padding()
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Invite Friend View
struct InviteFriendView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showShareSheet = false
    @State private var isSearching = false
    @State private var searchResult: UserSummary?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Search
                VStack(alignment: .leading, spacing: 8) {
                    Text("Search by email")
                        .font(.headline)

                    TextField("Email address", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()

                    Button {
                        Task {
                            await searchAndInviteUser()
                        }
                    } label: {
                        if isSearching {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("Search & Invite")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(searchText.isEmpty || isSearching ? Color.gray.opacity(0.3) : .uchicagoMaroon)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(searchText.isEmpty || isSearching)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    if let result = searchResult {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Invite sent to \(result.firstName)!")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Divider
                HStack {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 1)
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 1)
                }

                // Share link
                Button {
                    showShareSheet = true
                } label: {
                    HStack {
                        Image(systemName: "link")
                        Text("Share Invite Link")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .foregroundColor(.uchicagoMaroon)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Invite Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: ["Join my duo on DuoDating! https://duodating.app/invite/abc123"])
            }
        }
    }

    private func searchAndInviteUser() async {
        guard let currentUserId = appState.currentUser?.id else {
            errorMessage = "You must be logged in to send invites"
            return
        }

        isSearching = true
        errorMessage = nil
        searchResult = nil

        do {
            // Search for user by email
            guard let foundUser = try await ServiceContainer.shared.userService.searchUserByEmail(email: searchText) else {
                errorMessage = "No user found with email: \(searchText)"
                isSearching = false
                return
            }

            // Check if trying to invite self
            if foundUser.id == currentUserId {
                errorMessage = "You can't invite yourself!"
                isSearching = false
                return
            }

            // Send invite
            let invite = try await ServiceContainer.shared.pairService.sendInvite(
                fromUserId: currentUserId,
                toUserId: foundUser.id
            )

            // Update app state
            appState.outgoingInvites.append(invite)

            // Show success
            searchResult = foundUser
            searchText = ""

            print("✅ Invite sent successfully to \(foundUser.firstName)")

            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                dismiss()
            }

        } catch {
            errorMessage = "Failed to send invite: \(error.localizedDescription)"
            print("❌ Send invite error: \(error)")
        }

        isSearching = false
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Duo Preview View
struct DuoPreviewView: View {
    let duo: Duo

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("This is how other duos see you")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top)

                // Preview card
                GeometryReader { geometry in
                    DuoCard(duo: duo, isTop: true)
                        .frame(height: geometry.size.width * 1.3)
                }
                .aspectRatio(1/1.3, contentMode: .fit)
                .padding(.horizontal)
            }
        }
        .navigationTitle("Duo Preview")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Edit Duo Bio View
struct EditDuoBioView: View {
    let duo: Duo
    @Environment(\.dismiss) private var dismiss
    @State private var duoBio: String = ""

    var body: some View {
        Form {
            Section("Duo Bio") {
                TextEditor(text: $duoBio)
                    .frame(minHeight: 150)
            }

            Section {
                Text("This bio appears on your duo's profile and helps other duos get to know you both!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Edit Duo Bio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    // Save bio
                    dismiss()
                }
            }
        }
        .onAppear {
            duoBio = duo.duoBio
        }
    }
}

// MARK: - Duo Profile View (Other Duo)
struct DuoProfileView: View {
    @EnvironmentObject var appState: AppState
    let duo: Duo

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Photos section - both users
                TabView {
                    // Combined photo
                    HStack(spacing: 0) {
                        if let user1 = duo.user1 {
                            UserPhotoView(user: user1, showInfo: false)
                        }
                        if let user2 = duo.user2 {
                            UserPhotoView(user: user2, showInfo: false)
                        }
                    }
                    .frame(height: 400)

                    // User 1 photos
                    if let user1 = duo.user1 {
                        ForEach(user1.photos) { photo in
                            AsyncImage(url: URL(string: photo.url)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                            }
                            .frame(height: 400)
                            .clipped()
                        }
                    }

                    // User 2 photos
                    if let user2 = duo.user2 {
                        ForEach(user2.photos) { photo in
                            AsyncImage(url: URL(string: photo.url)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                            }
                            .frame(height: 400)
                            .clipped()
                        }
                    }
                }
                .tabViewStyle(.page)
                .frame(height: 400)

                // Info section
                VStack(alignment: .leading, spacing: 16) {
                    // Names
                    if let user1 = duo.user1, let user2 = duo.user2 {
                        Text("\(user1.firstName), \(user1.age) & \(user2.firstName), \(user2.age)")
                            .font(.title.bold())
                    }

                    // University
                    if let uni = duo.user1?.university ?? duo.user2?.university {
                        Label(uni, systemImage: "building.columns")
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Duo bio
                    if !duo.duoBio.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About us")
                                .font(.headline)
                            Text(duo.duoBio)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Individual bios
                    if let user1 = duo.user1 {
                        UserBioSection(user: user1)
                    }

                    if let user2 = duo.user2 {
                        UserBioSection(user: user2)
                    }

                    Divider()

                    // Shared interests
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Our Interests")
                            .font(.headline)

                        FlowLayout(spacing: 8) {
                            ForEach(duo.combinedInterests) { interest in
                                Text("\(interest.emoji) \(interest.name)")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - User Bio Section
struct UserBioSection: View {
    let user: UserSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let photo = user.photos.first {
                    AsyncImage(url: URL(string: photo.url)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                }

                Text(user.firstName)
                    .font(.headline)
            }

            if !user.bio.isEmpty {
                Text(user.bio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(user.prompts, id: \.id) { prompt in
                VStack(alignment: .leading, spacing: 4) {
                    Text(prompt.question)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(prompt.answer)
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - FlowLayout Placeholder
struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        // A simple VStack for now, does not implement actual flow layout logic
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
    }
}

#Preview {
    NavigationStack {
        DuoManagementView()
            .environmentObject(AppState())
    }
}
