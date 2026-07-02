import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: Tab = .discover
    @State private var chatMatch: IdentifiedMatch?

    enum Tab: Int, CaseIterable {
        case discover
        case matches
        case duo
        case thingsToDo
        case profile

        var title: String {
            switch self {
            case .discover: return "Browse"
            case .matches: return "Matches"
            case .duo: return "Duo"
            case .thingsToDo: return "To Do"
            case .profile: return "Profile"
            }
        }

        var icon: String {
            switch self {
            case .discover: return "rectangle.stack.fill"
            case .matches: return "heart.text.square.fill"
            case .duo: return "person.2.fill"
            case .thingsToDo: return "map.fill"
            case .profile: return "person.crop.circle.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Canonical Browse (reads duo_profile). Replaces the dead-schema DiscoverView.
            BrowseView()
                .tabItem {
                    Label(Tab.discover.title, systemImage: Tab.discover.icon)
                }
                .tag(Tab.discover)

            // Canonical matches + live chat (reads match/chat_message via Realtime).
            MatchListView()
                .tabItem {
                    Label(Tab.matches.title, systemImage: Tab.matches.icon)
                }
                .tag(Tab.matches)

            DuoManagementView()
                .tabItem {
                    Label(Tab.duo.title, systemImage: Tab.duo.icon)
                }
                .tag(Tab.duo)
                .badge(appState.pendingInvites.count)

            ThingsToDoView()
                .tabItem {
                    Label(Tab.thingsToDo.title, systemImage: Tab.thingsToDo.icon)
                }
                .tag(Tab.thingsToDo)

            ProfileView()
                .tabItem {
                    Label(Tab.profile.title, systemImage: Tab.profile.icon)
                }
                .tag(Tab.profile)
        }
        .tint(.uchicagoMaroon)
        // Live match banner, above all tabs.
        .overlay(alignment: .top) {
            if let banner = appState.matchBanner {
                MatchBannerView(
                    data: banner,
                    onSayHi: {
                        chatMatch = IdentifiedMatch(id: banner.matchId)
                        appState.matchBanner = nil
                    },
                    onDismiss: { withAnimation { appState.matchBanner = nil } }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: appState.matchBanner)
        .sheet(item: $chatMatch) { m in
            NavigationStack { MatchChatView(matchId: m.id) }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
