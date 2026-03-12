import SwiftUI

struct ReceiptStatusPill: View {
    let title: String
    let tint: Color
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }
}
