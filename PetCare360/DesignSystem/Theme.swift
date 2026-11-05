import SwiftUI

/// PetCare 360 design system — exact brand palette from the master prompt.
enum PCColor {
    static let deepTeal = Color(hex: "#123C3A")       // Primary
    static let freshGreen = Color(hex: "#218A77")     // Secondary / Success
    static let warmIvory = Color(hex: "#F5F4EF")      // Background
    static let cardWhite = Color(hex: "#FFFFFF")
    static let softPeach = Color(hex: "#E6A56C")      // Accent
    static let charcoal = Color(hex: "#253431")       // Text
    static let secondaryText = Color(hex: "#788681")
    static let warningAmber = Color(hex: "#D99A36")
    static let errorRed = Color(hex: "#D85B5B")
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

struct PCCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(PCColor.cardWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func pcCard() -> some View { modifier(PCCard()) }
}

struct PCPrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(PCColor.deepTeal)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel(title)
    }
}

struct PCEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(PCColor.freshGreen)
                .accessibilityHidden(true)
            Text(title).font(.headline).foregroundStyle(PCColor.charcoal)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(PCColor.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

struct PCSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(PCColor.charcoal)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
