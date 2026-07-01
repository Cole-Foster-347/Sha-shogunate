import SwiftUI
import GoogleSignIn
import GoogleSignInSwift

/// Login view with email/password and Google Sign-In
struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss: DismissAction

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showForgotPassword = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.uchicagoMaroon.gradient)

                    Text("Welcome Back")
                        .font(.title.bold())

                    Text("Sign in to continue")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                // Email/Password form
                VStack(spacing: 16) {
                    // Email field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        TextField("email@example.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Password field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        HStack {
                            if showPassword {
                                TextField("Password", text: $password)
                                    .textContentType(.password)
                            } else {
                                SecureField("Password", text: $password)
                                    .textContentType(.password)
                            }

                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Forgot password
                    Button {
                        showForgotPassword = true
                    } label: {
                        Text("Forgot Password?")
                            .font(.subheadline)
                            .foregroundStyle(.uchicagoMaroon)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 24)

                // Error message
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                }

                // Sign in button
                Button {
                    Task {
                        await signInWithEmail()
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Sign In")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .background(.uchicagoMaroon.gradient)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .disabled(isLoading || !isFormValid)
                .opacity(isFormValid ? 1.0 : 0.6)
                .padding(.horizontal, 24)

                // Divider
                HStack {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 1)
                    Text("OR")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 1)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

                // Google Sign-In button
                Button {
                    Task {
                        await signInWithGoogle()
                    }
                } label: {
                    HStack {
                        Image(systemName: "globe")
                            .font(.title3)
                        Text("Continue with Google")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white)
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                }
                .disabled(isLoading)
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
        }
    }

    // MARK: - Computed Properties

    private var isFormValid: Bool {
        !email.isEmpty &&
        !password.isEmpty &&
        authService.isValidEmail(email)
    }

    // MARK: - Actions

    private func signInWithEmail() async {
        errorMessage = nil
        isLoading = true

        do {
            _ = try await authService.signIn(email: email, password: password)

            // Success - AppState will handle navigation
            await appState.loadUserData()
            dismiss()

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func signInWithGoogle() async {
        errorMessage = nil
        isLoading = true

        do {
            // Get the root view controller
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                throw AuthError.googleSignInFailed("Could not find root view controller")
            }

            _ = try await authService.signInWithGoogle(presentingViewController: rootViewController)

            // Success - AppState will handle navigation
            await appState.loadUserData()
            dismiss()

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    NavigationStack {
        LoginView()
            .environmentObject(AuthService())
            .environmentObject(AppState())
    }
}
