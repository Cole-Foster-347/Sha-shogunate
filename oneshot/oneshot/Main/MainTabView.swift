import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: Tab = .discover

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

            MatchesView()
                .tabItem {
                    Label(Tab.matches.title, systemImage: Tab.matches.icon)
                }
                .tag(Tab.matches)
                .badge(appState.matches.filter { $0.unreadCount > 0 }.count)

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
        .tint(.pink)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
