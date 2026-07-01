import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile header
                    ProfileHeaderView()

                    // Quick actions
                    QuickActionsSection()

                    // Profile sections
                    ProfileSectionsView()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Profile")
        }
    }
}

// MARK: - Profile Header View
struct ProfileHeaderView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            // Main photo
            if let photo = appState.currentUser?.photos.first {
                AsyncImage(url: URL(string: photo.url)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.uchicagoMaroon, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Text(appState.currentUser?.firstName.prefix(1) ?? "")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.white)
                        }
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 4))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            }

            VStack(spacing: 4) {
                if let user = appState.currentUser {
                    Text("\(user.firstName), \(user.age)")
                        .font(.title2.bold())

                    if let university = user.university {
                        Text(university)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Verification badges (placeholder)
            HStack(spacing: 8) {
                Label("Verified", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Quick Actions Section
struct QuickActionsSection: View {
    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(destination: EditProfileView()) {
                QuickActionButton(
                    icon: "pencil",
                    title: "Edit Profile",
                    color: .uchicagoMaroon
                )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: ProfilePreviewView()) {
                QuickActionButton(
                    icon: "eye.fill",
                    title: "Preview",
                    color: .purple
                )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: DuoManagementView()) {
                QuickActionButton(
                    icon: "person.2.fill",
                    title: "My Duo",
                    color: .orange
                )
            }
            .buttonStyle(.plain)
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 50, height: 50)
                .background(color.opacity(0.1))
                .clipShape(Circle())

            Text(title)
                .font(.caption)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Profile Sections View
struct ProfileSectionsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            // Photos section
            ProfileSection(title: "Photos") {
                NavigationLink(destination: EditPhotosView()) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(appState.currentUser?.photos ?? []) { photo in
                                AsyncImage(url: URL(string: photo.url)) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                }
                                .frame(width: 80, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            // Add more button
                            if (appState.currentUser?.photos.count ?? 0) < 6 {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.tertiarySystemBackground))
                                    .frame(width: 80, height: 100)
                                    .overlay {
                                        Image(systemName: "plus")
                                            .font(.title2)
                                            .foregroundColor(.uchicagoMaroon)
                                    }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            // Bio section
            ProfileSection(title: "About Me") {
                NavigationLink(destination: EditBioView()) {
                    Text(appState.currentUser?.bio ?? "Add a bio...")
                        .font(.subheadline)
                        .foregroundColor(appState.currentUser?.bio.isEmpty ?? true ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            // Prompts section
            ProfileSection(title: "Prompts") {
                NavigationLink(destination: EditPromptsView()) {
                    VStack(spacing: 8) {
                        if let prompts = appState.currentUser?.prompts, !prompts.isEmpty {
                            ForEach(prompts) { prompt in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(prompt.question)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(prompt.answer)
                                        .font(.subheadline)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(.tertiarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        } else {
                            Text("Add prompts to show your personality")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            // Education section
            ProfileSection(title: "Education") {
                NavigationLink(destination: EditEducationView()) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let university = appState.currentUser?.university {
                            Label(university, systemImage: "building.columns")
                                .font(.subheadline)
                        }
                        if let major = appState.currentUser?.major {
                            Label(major, systemImage: "book")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if appState.currentUser?.university == nil && appState.currentUser?.major == nil {
                            Text("Add your education")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            // Location section
            ProfileSection(title: "Location") {
                NavigationLink(destination: EditLocationView()) {
                    HStack {
                        Label(appState.currentUser?.location.displayName ?? "London", systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Profile Section
struct ProfileSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Edit Profile View
struct EditProfileView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            NavigationLink("Photos", destination: EditPhotosView())
            NavigationLink("Bio", destination: EditBioView())
            NavigationLink("Prompts", destination: EditPromptsView())
            NavigationLink("Interests", destination: EditInterestsView())
            NavigationLink("Education", destination: EditEducationView())
            NavigationLink("Location", destination: EditLocationView())
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import PhotosUI

// MARK: - Edit Photos View
struct EditPhotosView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack {
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(0..<6, id: \.self) { index in
                        if let photos = appState.currentUser?.photos, index < photos.count {
                            // Existing Photo
                            AsyncImage(url: URL(string: photos[index].url)) { phase in
                                switch phase {
                                case .empty:
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay(ProgressView())
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                case .failure:
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay {
                                            Image(systemName: "exclamationmark.triangle")
                                                .foregroundColor(.red)
                                        }
                                @unknown default:
                                    Rectangle().fill(Color.gray.opacity(0.3))
                                }
                            }
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    Task {
                                        await appState.deletePhoto(photoId: photos[index].id)
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.5))
                                }
                                .offset(x: 8, y: -8)
                            }
                        } else {
                            // Add Photo Button
                            PhotosPicker(selection: $selectedItem, matching: .images) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground))
                                    .frame(height: 150)
                                    .overlay {
                                        if isUploading && index == (appState.currentUser?.photos.count ?? 0) {
                                            ProgressView()
                                        } else {
                                            VStack {
                                                Image(systemName: "plus")
                                                    .font(.title2)
                                                if index == 0 {
                                                    Text("Main")
                                                        .font(.caption)
                                                }
                                            }
                                            .foregroundColor(.uchicagoMaroon)
                                        }
                                    }
                            }
                            // Disable if we already have this many photos or if another upload is in progress
                            // Only enable the NEXT available slot
                            .disabled(isUploading || index != (appState.currentUser?.photos.count ?? 0))
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Edit Photos")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedItem) { newItem in
            if let newItem = newItem {
                Task {
                    isUploading = true
                    errorMessage = nil
                    do {
                        if let data = try await newItem.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            await appState.uploadPhoto(image: uiImage)
                        }
                    } catch {
                        errorMessage = "Failed to load image: \(error.localizedDescription)"
                    }
                    isUploading = false
                    selectedItem = nil
                }
            }
        }
    }
}

// MARK: - Edit Bio View
struct EditBioView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var bio: String = ""
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                TextEditor(text: $bio)
                    .frame(minHeight: 150)
            } header: {
                Text("About Me")
            } footer: {
                Text("Write something that represents you!")
            }
        }
        .navigationTitle("Edit Bio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        isSaving = true
                        await appState.updateProfile(bio: bio)
                        isSaving = false
                        dismiss()
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving)
            }
        }
        .onAppear {
            bio = appState.currentUser?.bio ?? ""
        }
    }
}

// MARK: - Edit Prompts View
struct EditPromptsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showPromptPicker = false

    var body: some View {
        List {
            if let prompts = appState.currentUser?.prompts {
                ForEach(prompts) { prompt in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prompt.question)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(prompt.answer)
                    }
                }
                .onDelete { indexSet in
                    // Delete prompt
                }
            }

            Button {
                showPromptPicker = true
            } label: {
                Label("Add Prompt", systemImage: "plus")
            }
        }
        .navigationTitle("Edit Prompts")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPromptPicker) {
            PromptPickerView(prompts: Binding(
                get: { appState.currentUser?.prompts ?? [] },
                set: { appState.currentUser?.prompts = $0 }
            ))
        }
    }
}

// MARK: - Edit Education View
struct EditEducationView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var university: String = ""
    @State private var major: String = ""
    @State private var isSaving = false

    var body: some View {
        Form {
            Section("University") {
                TextField("University name", text: $university)
            }

            Section("Major") {
                TextField("Your major", text: $major)
            }
        }
        .navigationTitle("Education")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        isSaving = true
                        // Trim whitespace
                        let newUniversity = university.trimmingCharacters(in: .whitespacesAndNewlines)
                        let newMajor = major.trimmingCharacters(in: .whitespacesAndNewlines)

                        // Pass nil if empty to clear the field in DB
                        let uniToSave = newUniversity.isEmpty ? nil : newUniversity
                        let majorToSave = newMajor.isEmpty ? nil : newMajor

                        await appState.updateProfile(university: uniToSave, major: majorToSave)

                        // Update local state immediately for UI responsiveness
                        if var currentUser = appState.currentUser {
                            currentUser.university = uniToSave
                            currentUser.major = majorToSave
                            appState.currentUser = currentUser
                        }

                        isSaving = false
                        dismiss()
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving)
            }
        }
        .onAppear {
            university = appState.currentUser?.university ?? ""
            major = appState.currentUser?.major ?? ""
        }
    }
}

// MARK: - Edit Location View
struct EditLocationView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLocation: UserLocation = .london
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                Picker("Location", selection: $selectedLocation) {
                    ForEach(UserLocation.allCases, id: \.self) { location in
                        HStack {
                            Text(location.displayName)
                            Spacer()
                            if location == .london {
                                Text("🇬🇧")
                            } else {
                                Text("🇺🇸")
                            }
                        }
                        .tag(location)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("Choose your location")
            } footer: {
                Text("This determines which area's activities and venues you'll see in Things to Do.")
            }
        }
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        isSaving = true
                        await appState.updateProfile(location: selectedLocation)

                        // Update local state immediately for UI responsiveness
                        if var currentUser = appState.currentUser {
                            currentUser.location = selectedLocation
                            appState.currentUser = currentUser
                        }

                        isSaving = false
                        dismiss()
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving)
            }
        }
        .onAppear {
            selectedLocation = appState.currentUser?.location ?? .london
        }
    }
}

// MARK: - Profile Preview View
struct ProfilePreviewView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("This is how others see you")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Mock card preview
                if let user = appState.currentUser {
                    ProfileCardPreview(user: user)
                }
            }
            .padding()
        }
        .navigationTitle("Profile Preview")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ProfileCardPreview: View {
    let user: User

    var body: some View {
        VStack(spacing: 0) {
            // Photo
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
                                .font(.system(size: 80, weight: .bold))
                                .foregroundColor(.white)
                        }
                }
                .frame(height: 400)
                .clipped()
            }

            // Info
            VStack(alignment: .leading, spacing: 12) {
                Text("\(user.firstName), \(user.age)")
                    .font(.title2.bold())

                if let university = user.university {
                    Label(university, systemImage: "building.columns")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !user.bio.isEmpty {
                    Text(user.bio)
                        .font(.subheadline)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(user.interests.prefix(5)) { interest in
                            Text("\(interest.emoji) \(interest.name)")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Edit Interests View
struct EditInterestsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var interests: [Interest] = []

    var body: some View {
        Form {
            Section {
                Text("Edit Interests functionality goes here.")
            } header: {
                Text("Interests")
            } footer: {
                Text("Select your interests to help us match you better.")
            }
        }
        .navigationTitle("Edit Interests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    // For now, no actual saving logic.
                    // In a real implementation, you would update appState.currentUser.interests
                    // Example: appState.currentUser?.interests = interests
                    dismiss()
                }
            }
        }
        .onAppear {
            interests = appState.currentUser?.interests ?? []
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState())
}
