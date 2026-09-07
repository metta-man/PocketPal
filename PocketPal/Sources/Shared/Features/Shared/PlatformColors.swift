import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    static var personalBackground: Color {
        receiptAdaptiveColor(light: (0.98, 0.95, 0.90), dark: (0.12, 0.10, 0.09))
    }
    static var personalAccent: Color {
        receiptAdaptiveColor(light: (0.57, 0.27, 0.13), dark: (0.94, 0.65, 0.41))
    }

    static var receiptCardBackground: Color {
        receiptAdaptiveColor(light: (1.0, 1.0, 1.0), dark: (0.13, 0.14, 0.17))
    }

    static var receiptElevatedBackground: Color {
        receiptAdaptiveColor(light: (0.96, 0.98, 1.0), dark: (0.17, 0.18, 0.22))
    }

    static var receiptGroupedBackground: Color {
        receiptAdaptiveColor(light: (0.94, 0.96, 0.99), dark: (0.07, 0.08, 0.10))
    }

    static var receiptSecondaryFill: Color {
        receiptAdaptiveColor(light: (0.91, 0.94, 0.99), dark: (0.20, 0.22, 0.27))
    }

    static var receiptPreviewBackground: Color {
        receiptAdaptiveColor(light: (0.90, 0.93, 0.98), dark: (0.10, 0.11, 0.14))
    }

    static var receiptOutline: Color {
        receiptAdaptiveColor(light: (0.78, 0.82, 0.90), dark: (0.34, 0.37, 0.44))
    }

    static var receiptAccentBlue: Color { Color(red: 0.08, green: 0.32, blue: 0.96) }
    static var receiptAccentGreen: Color { Color(red: 0.00, green: 0.66, blue: 0.49) }
    static var receiptAccentOrange: Color { Color(red: 1.00, green: 0.49, blue: 0.08) }
    static var receiptAccentRed: Color { Color(red: 0.90, green: 0.18, blue: 0.24) }
    static var receiptAccentViolet: Color { Color(red: 0.50, green: 0.22, blue: 0.94) }
    static var receiptAccentCyan: Color { Color(red: 0.00, green: 0.64, blue: 0.86) }
    static var receiptAccentRose: Color { Color(red: 0.95, green: 0.24, blue: 0.54) }

    private static func receiptAdaptiveColor(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let source = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: source.0, green: source.1, blue: source.2, alpha: 1)
        })
        #elseif canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let source = isDark ? dark : light
            return NSColor(red: source.0, green: source.1, blue: source.2, alpha: 1)
        })
        #else
        Color(red: light.0, green: light.1, blue: light.2)
        #endif
    }
}

extension ShapeStyle where Self == Color {
    static var receiptAccentBlue: Color { .receiptAccentBlue }
    static var receiptAccentGreen: Color { .receiptAccentGreen }
    static var receiptAccentOrange: Color { .receiptAccentOrange }
    static var receiptAccentRed: Color { .receiptAccentRed }
    static var receiptAccentViolet: Color { .receiptAccentViolet }
    static var receiptAccentCyan: Color { .receiptAccentCyan }
    static var receiptAccentRose: Color { .receiptAccentRose }
}
