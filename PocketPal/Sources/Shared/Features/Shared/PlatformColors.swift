import SwiftUI

extension Color {
    static var receiptCardBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var receiptGroupedBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var receiptSecondaryFill: Color {
        #if canImport(UIKit)
        Color(uiColor: .tertiarySystemBackground)
        #else
        Color(nsColor: .textBackgroundColor)
        #endif
    }
}
