//
//  ExpenseTheme.swift
//  Splitty
//

import SwiftUI
import UIKit

/// The expense sheet's palette, pinned to exact values rather than to the system's
/// semantic colours.
///
/// `systemBackground` is pure black in dark mode, which is not the surface this sheet is
/// meant to be, and the pad is hosted in UIKit — both sides need the same colour from one
/// definition or the seam comes back.
enum ExpenseTheme {
    /// The sheet's surface, and the pad's.
    static let background = dynamic(dark: 0x1C1C1E, light: 0xFEFEFE)

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
