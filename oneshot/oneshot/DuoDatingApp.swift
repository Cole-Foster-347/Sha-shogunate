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
                // Not logged in - show welcome/auth screen
                WelcomeView()
            } else if !appState.isOnboardingComplete {
                // Logged in but not onboarded
                OnboardingContainerView()
            } else if appState.currentDuo == nil {
                // Onboarded but no duo
                DuoRequiredView()
            } else {
                // Fully set up - show main app
                MainTabView()
            }
        }
        .animation(.easeInOut, value: appState.isOnboardingComplete)
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
