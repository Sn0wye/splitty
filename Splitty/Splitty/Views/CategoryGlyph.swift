//
//  CategoryGlyph.swift
//  Splitty
//

import SwiftUI

/// A category's icon, sized and tinted by `.font` and `.foregroundStyle` like the SF Symbol it
/// usually is. `general` draws the coin of the group's currency; a currency with no matching SF
/// Symbol coin gets its code cut out of a plain one.
struct CategoryGlyph: View {
    let category: ExpenseCategory

    @Environment(\.currency) private var currency

    var body: some View {
        if let glyph = category.glyph ?? currency.coinGlyph {
            Image(systemName: glyph)
        } else {
            Image(systemName: "circle.fill")
                .overlay {
                    GeometryReader { proxy in
                        Text(currency.code)
                            .font(.system(size: proxy.size.height * 0.3, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
        }
    }
}
