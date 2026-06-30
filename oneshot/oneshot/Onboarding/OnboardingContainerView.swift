import SwiftUI

struct OnboardingContainerView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                OnboardingProgressView(currentStep: appState.onboardingStep)
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Content
                TabView(selection: $appState.onboardingStep) {
                    OnboardingBasicsView()
                        .tag(OnboardingStep.basics)

                    OnboardingPhotosView()
                        .tag(OnboardingStep.photos)

                    OnboardingProfileView()
                        .tag(OnboardingStep.profile)

                    OnboardingDuoView()
                        .tag(OnboardingStep.duo)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: appState.onboardingStep)
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Progress View
struct OnboardingProgressView: View {
    let currentStep: OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.pink : Color.gray.opacity(0.3))
                    .frame(height: 4)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Step 1: Basics
struct OnboardingBasicsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showDatePicker = false

    private var isValid: Bool {
        !appState.onboardingFirstName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("The Basics")
                        .font(.largeTitle.bold())

                    Text("Let's start with some basics about you")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                // First Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("First name")
                        .font(.headline)

                    TextField("Your first name", text: $appState.onboardingFirstName)
                        .textFieldStyle(OnboardingTextFieldStyle())
                }

                // Birthday
                VStack(alignment: .leading, spacing: 8) {
                    Text("Birthday")
                        .font(.headline)

                    Button {
                        showDatePicker.toggle()
                    } label: {
                        HStack {
                            Text(appState.onboardingBirthday, style: .date)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "calendar")
                                .foregroundColor(.pink)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if showDatePicker {
                        DatePicker(
                            "Birthday",
                            selection: $appState.onboardingBirthday,
                            in: ...Calendar.current.date(byAdding: .year, value: -18, to: Date())!,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                    }
                }

                // Gender
                VStack(alignment: .leading, spacing: 8) {
                    Text("I am a...")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(Gender.allCases, id: \.self) { gender in
                            SelectionButton(
                                title: gender.rawValue,
                                isSelected: appState.onboardingGender == gender
                            ) {
                                appState.onboardingGender = gender
                            }
                        }
                    }
                }

                // Gender Preference
                VStack(alignment: .leading, spacing: 8) {
                    Text("Show me...")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(GenderPreference.allCases, id: \.self) { preference in
                            SelectionButton(
                                title: preference.rawValue,
                                isSelected: appState.onboardingGenderPreference == preference
                            ) {
                                appState.onboardingGenderPreference = preference
                            }
                        }
                    }
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 24)
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingNextButton(title: "Continue", isEnabled: isValid) {
                appState.onboardingStep = .photos
            }
        }
    }
}

// MARK: - Step 2: Photos
struct OnboardingPhotosView: View {
    @EnvironmentObject var appState: AppState
    @State private var showImagePicker = false
    @State private var selectedImageIndex: Int?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var isValid: Bool {
        appState.onboardingPhotos.count >= 3
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Photos")
                        .font(.largeTitle.bold())

                    Text("Add at least 3 photos of yourself")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                // Photo Grid
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<6, id: \.self) { index in
                        PhotoSlotView(
                            image: index < appState.onboardingPhotos.count ? appState.onboardingPhotos[index] : nil,
                            index: index,
                            onTap: {
                                selectedImageIndex = index
                                showImagePicker = true
                            },
                            onDelete: {
                                if index < appState.onboardingPhotos.count {
                                    appState.onboardingPhotos.remove(at: index)
                                }
                            }
                        )
                    }
                }

                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Label("Drag to reorder", systemImage: "arrow.up.arrow.down")
                    Label("Face clearly visible", systemImage: "face.smiling")
                    Label("No group photos for first pic", systemImage: "person.fill")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 24)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button("Back") {
                    appState.onboardingStep = .basics
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                OnboardingNextButton(title: "Continue", isEnabled: isValid) {
                    appState.onboardingStep = .profile
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(images: $appState.onboardingPhotos, selectedIndex: selectedImageIndex)
        }
    }
}

// MARK: - Photo Slot View
struct PhotoSlotView: View {
    let image: UIImage?
    let index: Int
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture(perform: onTap)

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .offset(x: 8, y: -8)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 150)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.title2)
                            if index == 0 {
                                Text("Main")
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(.pink)
                    }
                    .onTapGesture(perform: onTap)
            }
        }
    }
}

// MARK: - Step 3: Profile
struct OnboardingProfileView: View {
    @EnvironmentObject var appState: AppState
    @State private var showPromptPicker = false

    private var isValid: Bool {
        !appState.onboardingBio.trimmingCharacters(in: .whitespaces).isEmpty &&
        appState.onboardingInterests.count >= 3
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Profile")
                        .font(.largeTitle.bold())

                    Text("Tell us about yourself")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                // Bio
                VStack(alignment: .leading, spacing: 8) {
                    Text("About me")
                        .font(.headline)

                    TextEditor(text: $appState.onboardingBio)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                }

                // Prompts
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Prompts")
                            .font(.headline)
                        Spacer()
                        Button("Add") {
                            showPromptPicker = true
                        }
                        .foregroundColor(.pink)
                    }

                    if appState.onboardingPrompts.isEmpty {
                        Text("Add prompts to show your personality")
                            .foregroundStyle(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        ForEach(appState.onboardingPrompts) { prompt in
                            PromptCard(prompt: prompt) {
                                appState.onboardingPrompts.removeAll { $0.id == prompt.id }
                            }
                        }
                    }
                }

                // University & Major
            } // Closes VStack (line 306)
        } // Closes ScrollView (line 305)
    } // Closes body (line 304)
} // Closes struct OnboardingProfileView (line 295)

struct OnboardingDuoView: View {
    @EnvironmentObject var appState: AppState

    enum Mode { case choose, create, join }
    @State private var mode: Mode = .choose
    @State private var enteredCode: String = ""

    var body: some View {
        Group {
            switch mode {
            case .choose: chooseView
            case .create: createView
            case .join:   joinView
            }
        }
        .animation(.easeInOut, value: mode)
    }

    // MARK: A or B chooser

    private var chooseView: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.pink.gradient)
                Text("Find Your Duo")
                    .font(.largeTitle.bold())
                // CLAUDE.md §9 tagline
                Text("Meet as a pair. 45 minutes. Zero pressure.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        await appState.createInvite()
                        if appState.activeInviteCode != nil { mode = .create }
                    }
                } label: {
                    Label("Create a duo", systemImage: "plus.circle.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .background(.pink.gradient).foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button { mode = .join } label: {
                    Label("Join with a code", systemImage: "arrow.right.circle.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .background(Color(.secondarySystemBackground))
                        .foregroundColor(.pink)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: Creator (A) — show code, wait for accept

    private var createView: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("Share this code with your duo partner")
                .font(.headline).multilineTextAlignment(.center)

            Text(appState.activeInviteCode ?? "…")
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .padding(.vertical, 24).padding(.horizontal, 32)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Text("They enter it on their phone to form your duo. Tap Continue once they've accepted.")
                .font(.subheadline).multilineTextAlignment(.center)
                .foregroundStyle(.secondary).padding(.horizontal, 32)

            if let msg = appState.errorMessage {
                Text(msg).font(.footnote).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }

            Spacer()

            Button {
                Task { await appState.confirmInviteAccepted() }
            } label: {
                Group {
                    if appState.isLoading { ProgressView().tint(.white) }
                    else { Text("Continue") }
                }
                .font(.headline).frame(maxWidth: .infinity).padding()
                .background(.pink.gradient).foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(appState.isLoading)
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }

    // MARK: Accepter (B) — enter code

    private var joinView: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("Enter your partner's code")
                .font(.headline)

            TextField("PINE-4823", text: $enteredCode)
                .font(.system(.title2, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 32)

            if let msg = appState.errorMessage {
                Text(msg).font(.footnote).foregroundColor(.pink)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task { await appState.acceptInvite(code: enteredCode) }
                } label: {
                    Group {
                        if appState.isLoading { ProgressView().tint(.white) }
                        else { Text("Join duo") }
                    }
                    .font(.headline).frame(maxWidth: .infinity).padding()
                    .background(.pink.gradient).foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(appState.isLoading || enteredCode.trimmingCharacters(in: .whitespaces).isEmpty)

                Button { mode = .choose; appState.errorMessage = nil } label: {
                    Text("Back").font(.subheadline).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }
}

// MARK: - Duo Explainer Row
struct DuoExplainerRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.pink)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Supporting Views
struct OnboardingTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SelectionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isSelected ? Color.pink : Color(.secondarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.pink : Color.clear, lineWidth: 2)
                )
        }
    }
}

struct OnboardingNextButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isEnabled ? Color.clear : Color.gray.opacity(0.3))
                .backgroundStyle(isEnabled ? AnyShapeStyle(.pink.gradient) : AnyShapeStyle(Color.clear))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(!isEnabled)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Prompt Card
struct PromptCard: View {
    let prompt: ProfilePrompt
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(prompt.question)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Text(prompt.answer)
                .font(.subheadline)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Prompt Picker View
struct PromptPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var prompts: [ProfilePrompt]
    @State private var selectedPrompt: PredefinedPrompt?
    @State private var customQuestion: String = ""
    @State private var answer: String = ""

    var body: some View {
        NavigationStack {
            List {
                if let selected = selectedPrompt {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            if selected == .custom {
                                TextField("Write your own prompt...", text: $customQuestion)
                                    .font(.headline)
                            } else {
                                Text(selected.rawValue)
                                    .font(.headline)
                            }

                            TextField("Your answer...", text: $answer, axis: .vertical)
                                .lineLimit(3...6)

                            Button("Save") {
                                let question = selected == .custom ? customQuestion : selected.rawValue
                                prompts.append(ProfilePrompt(question: question, answer: answer))
                                dismiss()
                            }
                            .disabled(
                                answer.trimmingCharacters(in: .whitespaces).isEmpty ||
                                (selected == .custom && customQuestion.trimmingCharacters(in: .whitespaces).isEmpty)
                            )
                        }
                        .padding(.vertical, 8)
                    }
                } else {
                    Section("Choose a prompt") {
                        ForEach(PredefinedPrompt.allCases, id: \.self) { prompt in
                            Button {
                                selectedPrompt = prompt
                            } label: {
                                Text(prompt.rawValue)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    var selectedIndex: Int?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                if let index = parent.selectedIndex, index < parent.images.count {
                    parent.images[index] = image
                } else {
                    parent.images.append(image)
                }
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    OnboardingContainerView()
        .environmentObject(AppState())
}
