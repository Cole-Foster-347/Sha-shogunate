import SwiftUI

/// Opening animation: two PAIRS (each a person.2 glyph = one duo) fly in from the
/// sides and snap together like magnets — two duos meeting — with a pulse ring at the
/// join, then the "Roomeet" wordmark rises. Calls `onFinish` after the sequence.
struct SplashView: View {
    var onFinish: () -> Void

    @State private var snapped = false      // pairs pulled together
    @State private var pulse = false        // magnetic snap ripple
    @State private var showName = false     // wordmark rises in

    var body: some View {
        ZStack {
            Color.uchicagoMaroon.ignoresSafeArea()

            // Two pairs snapping together
            ZStack {
                // magnetic snap ripple at the join
                Circle()
                    .stroke(Color.white.opacity(0.7), lineWidth: 3)
                    .frame(width: pulse ? 260 : 80, height: pulse ? 260 : 80)
                    .opacity(pulse ? 0 : 0.9)

                // left pair (one duo)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundColor(.white)
                    .offset(x: snapped ? -34 : -280)
                    .scaleEffect(snapped ? 1 : 0.85)

                // right pair (the other duo)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .offset(x: snapped ? 34 : 280)
                    .scaleEffect(snapped ? 1 : 0.85)
            }

            // Wordmark
            VStack(spacing: 6) {
                Spacer()
                Text("Roomeet")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(showName ? 1 : 0)
                    .offset(y: showName ? 0 : 14)
                Text("Meet as a pair.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .opacity(showName ? 1 : 0)
                Spacer().frame(height: 130)
            }
        }
        .onAppear { runSequence() }
    }

    private func runSequence() {
        // two pairs snap together with a bouncy, magnetic overshoot
        withAnimation(.spring(response: 0.5, dampingFraction: 0.42).delay(0.25)) {
            snapped = true
        }
        // ripple rides the snap
        withAnimation(.easeOut(duration: 0.7).delay(0.6)) {
            pulse = true
        }
        // wordmark rises after the snap
        withAnimation(.easeOut(duration: 0.5).delay(0.85)) {
            showName = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { onFinish() }
    }
}

#Preview {
    SplashView(onFinish: {})
}
