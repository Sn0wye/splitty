//
//  AppTabView.swift
//  Splitty
//

import SwiftUI

/// The app's tabs on the system tab bar: Liquid Glass on iOS 26, with content scrolling
/// under it. The bar only navigates. Adding an expense is an action, so it lives in the
/// toolbar of the screens it applies to, as `AddExpenseButton`.
struct AppTabView<Content: View>: View {
    @Binding var selection: AppTab
    @ViewBuilder let content: (AppTab) -> Content

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab) {
                    content(tab)
                }
            }
        }
        .tint(Color("brand"))
        .minimizingTabBarOnScroll()
        // Selection, not impact: moving between tabs is a picker landing on a detent, and
        // the system has a texture for exactly that.
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private extension View {
    @ViewBuilder
    func minimizingTabBarOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

/// The toolbar's add button, in Splitty Coral: the one coloured control in the bar.
/// Prominent glass where the system has it, a filled circle before that.
struct AddExpenseButton: View {
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            Label(L10n.Tabs.addExpense, systemImage: "plus")
        }
        .labelStyle(.iconOnly)
        .tint(Color("brand"))

        if #available(iOS 26.0, *) {
            button.buttonStyle(.glassProminent)
        } else {
            button
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
        }
    }
}
