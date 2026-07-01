import SwiftUI
import GoogleSignIn
import GoogleSignInSwift

/// Sign up view for creating new accounts
struct SignUpView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss: DismissAction

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var agreedToTerms = false
    @State private var showEmailConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.uchicagoMaroon.gradient)

                    Text("Create Account")
                        .font(.title.bold())

                    Text("Join thousands of double daters")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                // Sign up form
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

                        if !email.isEmpty && !authService.isValidEmail(email) {
                            Text("Please enter a valid email")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    // Password field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        HStack {
                            if showPassword {
                                TextField("At least 8 characters", text: $password)
                                    .textContentType(.newPassword)
                            } else {
                                SecureField("At least 8 characters", text: $password)
                                    .textContentType(.newPassword)
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

                        if !password.isEmpty && !authService.isValidPassword(password) {
                            Text("Password must be at least 8 characters")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    // Confirm password field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Password")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        HStack {
                            if showConfirmPassword {
                                TextField("Re-enter password", text: $confirmPassword)
                                    .textContentType(.newPassword)
                            } else {
                                SecureField("Re-enter password", text: $confirmPassword)
                                    .textContentType(.newPassword)
                            }

                            Button {
                                showConfirmPassword.toggle()
                            } label: {
                                Image(systemName: showConfirmPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        if !confirmPassword.isEmpty && password != confirmPassword {
                            Text("Passwords don't match")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    // Terms and conditions
                    HStack(alignment: .top, spacing: 12) {
                        Button {
                            agreedToTerms.toggle()
                        } label: {
                            Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundStyle(agreedToTerms ? .uchicagoMaroon : .secondary)
                        }

                        Text("I agree to the Terms of Service and Privacy Policy")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)

                // Error message
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Sign up button
                Button {
                    Task {
                        await signUpWithEmail()
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Create Account")
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
                        await signUpWithGoogle()
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
                .disabled(isLoading || !agreedToTerms)
                .opacity(agreedToTerms ? 1.0 : 0.6)
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("Check Your Email", isPresented: $showEmailConfirmation) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("We've sent you a confirmation email. Please check your inbox and click the link to verify your account.")
        }
    }

    // MARK: - Computed Properties

    private var isFormValid: Bool {
        !email.isEmpty &&
        !password.isEmpty &&
        !confirmPassword.isEmpty &&
        authService.isValidEmail(email) &&
        authService.isValidPassword(password) &&
        password == confirmPassword &&
        agreedToTerms
    }

    // MARK: - Actions

    private func signUpWithEmail() async {
        errorMessage = nil
        isLoading = true

        do {
            _ = try await authService.signUp(email: email, password: password)

            // Check if email confirmation is required
            if !authService.isAuthenticated {
                showEmailConfirmation = true
            } else {
                // User is signed in, proceed to onboarding
                await appState.loadUserData()
                dismiss()
            }

        } catch let error as AuthError {
            switch error {
            case .emailConfirmationRequired:
                showEmailConfirmation = true
            default:
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func signUpWithGoogle() async {
        errorMessage = nil
        isLoading = true

        do {
            // Get the root view controller
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                throw AuthError.googleSignInFailed("Could not find root view controller")
            }

            _ = try await authService.signInWithGoogle(presentingViewController: rootViewController)

            // Success - proceed to onboarding
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
        SignUpView()
            .environmentObject(AuthService())
            .environmentObject(AppState())
    }
}
