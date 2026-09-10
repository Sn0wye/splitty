//
//  ExpenseTheme.swift
//  Splitty
//

import SwiftUI
import UIKit

/// The money sheets' palette, pinned to exact values so their SwiftUI and UIKit
/// surfaces remain seamless.
enum ExpenseTheme {
    /// Matches the Balances drawer's deeper page surface in both appearances.
    static let background = dynamic(dark: 0x09090B, light: 0xF4F4F5)

    /// The amount and the keys.
    static let foreground = dynamic(dark: 0xFEFEFE, light: 0x000000)

    /// The one filled control: the forward arrow's disc. Its glyph is `background`.
    static let accent = dynamic(dark: 0xF3F3F4, light: 0x191919)

    private static func dynamic(dark: Int, light: Int) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }
    }
}

extension Color {
    static let expenseBackground = Color(ExpenseTheme.background)
    static let expenseForeground = Color(ExpenseTheme.foreground)
    static let expenseAccent = Color(ExpenseTheme.accent)
}

private extension UIColor {
    convenience init(hex: Int) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
