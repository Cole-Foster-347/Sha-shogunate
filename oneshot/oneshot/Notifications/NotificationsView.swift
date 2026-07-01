import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            Group {
                if appState.notifications.isEmpty {
                    EmptyNotificationsView()
                } else {
                    List {
                        ForEach(appState.notifications) { notification in
                            NotificationRow(notification: notification)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !appState.notifications.isEmpty {
                        Button("Clear All") {
                            appState.notifications.removeAll()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Notification Row
struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconBackgroundColor)
                    .frame(width: 44, height: 44)

                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(notification.title)
                    .font(.headline)

                Text(notification.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(notification.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if !notification.isRead {
                Circle()
                    .fill(.uchicagoMaroon)
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.vertical, 8)
        .opacity(notification.isRead ? 0.7 : 1)
    }

    private var iconName: String {
        switch notification.type {
        case .newMatch: return "heart.fill"
        case .newMessage: return "message.fill"
        case .duoInvite: return "person.badge.plus"
        case .duoInviteAccepted: return "checkmark.circle.fill"
        case .someoneLikedYou: return "star.fill"
        case .system: return "bell.fill"
        }
    }

    private var iconColor: Color {
        switch notification.type {
        case .newMatch: return .uchicagoMaroon
        case .newMessage: return .blue
        case .duoInvite: return .orange
        case .duoInviteAccepted: return .green
        case .someoneLikedYou: return .purple
        case .system: return .gray
        }
    }

    private var iconBackgroundColor: Color {
        iconColor.opacity(0.15)
    }
}

// MARK: - Empty Notifications View
struct EmptyNotificationsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Notifications")
                .font(.title2.bold())

            Text("When you get new matches, messages,\nor duo invites, they'll show up here.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    NotificationsView()
        .environmentObject(AppState())
}
