import SwiftUI

/// Forgot password view for requesting password reset
struct ForgotPasswordView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss: DismissAction

    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Icon
                    Image(systemName: "key.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.uchicagoMaroon.gradient)
                        .padding(.top, 48)

                    // Header
                    VStack(spacing: 8) {
                        Text("Reset Password")
                            .font(.title.bold())

                        Text("Enter your email and we'll send you a link to reset your password")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

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
                    .padding(.horizontal, 24)

                    // Error message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Send reset link button
                    Button {
                        Task {
                            await sendResetLink()
                        }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("Send Reset Link")
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

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Check Your Email", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("If an account exists with that email, we've sent you a password reset link. Please check your inbox.")
            }
        }
    }

    // MARK: - Computed Properties

    private var isFormValid: Bool {
        !email.isEmpty && authService.isValidEmail(email)
    }

    // MARK: - Actions

    private func sendResetLink() async {
        errorMessage = nil
        isLoading = true

        do {
            try await authService.sendPasswordReset(email: email)
            showSuccess = true

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    ForgotPasswordView()
        .environmentObject(AuthService())
}
