import SwiftUI

// Note: Main entry point is in oneshotApp.swift

// MARK: - Root View
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashView { withAnimation(.easeInOut(duration: 0.4)) { showSplash = false } }
                    .transition(.opacity)
            } else {
                content.transition(.opacity)
            }
        }
    }

    @ViewBuilder private var content: some View {
        Group {
            if !ServiceContainer.shared.authService.isAuthenticated {
                // Not logged in — welcome / login
                WelcomeView()
            } else if appState.currentDuo == nil {
                // Signed in, no active duo — create or join one
                DuoSetupView()
            } else {
                // Signed in with an active duo — the app
                MainTabView()
            }
        }
        .animation(.easeInOut, value: appState.currentDuo?.id)
    }
}

// MARK: - Duo Setup (signed in, no duo yet)
struct DuoSetupView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            OnboardingDuoView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Sign Out") { Task { await appState.signOut() } }
                            .foregroundColor(.uchicagoMaroon)
                    }
                }
        }
    }
}

// MARK: - Duo Required View
struct DuoRequiredView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "person.2.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.uchicagoMaroon.gradient)

                Text("Find Your Duo")
                    .font(.largeTitle.bold())

                Text("You need a duo partner to start swiping!\nInvite a friend or accept an invite.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Spacer()

                NavigationLink(destination: DuoManagementView()) {
                    Label("Set Up Your Duo", systemImage: "arrow.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.uchicagoMaroon.gradient)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
}
