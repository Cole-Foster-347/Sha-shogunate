import SwiftUI

/// Roomeet brand palette — University of Chicago maroon.
/// Defined on `ShapeStyle where Self == Color` so `.uchicagoMaroon` resolves in every
/// context the old `.pink` did: .foregroundStyle / .tint / .fill / .background(.uchicagoMaroon.gradient)
/// as well as plain `Color.uchicagoMaroon`.
extension ShapeStyle where Self == Color {
    /// UChicago Maroon (#800000).
    static var uchicagoMaroon: Color { Color(red: 0.50, green: 0.0, blue: 0.0) }

    /// A slightly lighter maroon for gradient highlights (#A31F34-ish).
    static var uchicagoMaroonLight: Color { Color(red: 0.64, green: 0.12, blue: 0.20) }

    /// UChicago Greystone accent (#737373).
    static var uchicagoGreystone: Color { Color(red: 0.45, green: 0.45, blue: 0.45) }
}

extension Color {
    /// Two-tone maroon gradient for hero buttons / backgrounds.
    static var roomeetGradient: LinearGradient {
        LinearGradient(colors: [.uchicagoMaroonLight, .uchicagoMaroon],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
