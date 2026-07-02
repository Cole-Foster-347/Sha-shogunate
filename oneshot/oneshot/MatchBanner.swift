import SwiftUI

/// Data for the live "It's a match" banner.
struct MatchBannerData: Identifiable, Equatable {
    let matchId: UUID
    let myPhoto: URL?
    let otherPhoto: URL?
    let otherBio: String
    var id: UUID { matchId }
}

/// Identifiable wrapper so a match id can drive a `.sheet(item:)`.
struct IdentifiedMatch: Identifiable, Equatable {
    let id: UUID
}

/// Slide-in banner: the two duos' photos animate together (the pair motif),
/// with §9 copy "You matched — say hi?" and a "Say hi" button. Maroon theme.
struct MatchBannerView: View {
    let data: MatchBannerData
    var onSayHi: () -> Void
    var onDismiss: () -> Void

    @State private var together = false

    var body: some View {
        VStack(spacing: 12) {
            // Two photos start apart and meet in the center.
            ZStack {
                photo(data.myPhoto).offset(x: together ? -22 : -130)
                photo(data.otherPhoto).offset(x: together ? 22 : 130)
            }
            .frame(height: 72)

            Text("You matched — say hi?")   // CLAUDE.md §9 exact
                .font(.headline)
                .foregroundColor(.white)

            Button(action: onSayHi) {
                Text("Say hi")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 26).padding(.vertical, 9)
                    .background(Color.white)
                    .foregroundColor(.uchicagoMaroon)
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 14).padding(.bottom, 16).padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(Color.roomeetGradient)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.85))
                    .padding(10)
            }
        }
        .padding(.horizontal, 12)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { together = true }
        }
        // swipe up to dismiss
        .gesture(DragGesture().onEnded { if $0.translation.height < -30 { onDismiss() } })
        // auto-dismiss after ~5s
        .task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            onDismiss()
        }
    }

    private func photo(_ url: URL?) -> some View {
        AsyncImage(url: url) { img in
            img.resizable().scaledToFill()
        } placeholder: {
            Color.white.opacity(0.25)
                .overlay(Image(systemName: "person.2.fill").foregroundColor(.white.opacity(0.8)))
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 3))
    }
}
