//
//  PrototypeGlassNavbar.swift
//  Splitty
//
//  PROTOTYPE, throwaway. Question: can the bottom bar be Liquid Glass?
//  Two variants on the real ContentView, switchable from the floating pill at the
//  top left (debug only) or `-SplittyNavbarVariant B` at launch.
//
//    A  Current flat bar with the raised add button (baseline)
//    B  Native TabView for navigation only; add moves to a coral glass "+" in the
//       toolbar of Groups (asks which group) and Group (adds to that group)
//
//  B needs iOS 26; below that it falls back to A.
//

import SwiftUI

enum PrototypeNavbarVariant: String, CaseIterable {
    case a = "A", b = "B"

    var name: String {
        switch self {
        case .a: "Current flat bar"
        case .b: "Native tabs, + on top"
        }
    }

    static var launch: PrototypeNavbarVariant {
        #if DEBUG
        // Read from the launch-argument domain only; never written.
        UserDefaults.standard.string(forKey: "SplittyNavbarVariant")
            .flatMap { PrototypeNavbarVariant(rawValue: $0.uppercased()) } ?? .a
        #else
        .a
        #endif
    }
}

// MARK: - Switcher

struct PrototypeNavbarSwitcher: View {
    @Binding var variant: PrototypeNavbarVariant

    var body: some View {
        #if DEBUG
        HStack(spacing: 4) {
            arrow("chevron.left", step: -1)
            Text(verbatim: variant.rawValue)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .lineLimit(1)
            arrow("chevron.right", step: 1)
        }
        .foregroundStyle(.yellow)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.black, in: Capsule())
        .overlay(Capsule().strokeBorder(.yellow.opacity(0.6), lineWidth: 1))
        .shadow(radius: 6)
        #endif
    }

    private func arrow(_ symbol: String, step: Int) -> some View {
        Button {
            let all = PrototypeNavbarVariant.allCases
            let index = all.firstIndex(of: variant)!
            variant = all[(index + step + all.count) % all.count]
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - B: native TabView, add in the toolbar

@available(iOS 26.0, *)
struct PrototypeNativeTabShell<Content: View>: View {
    @Binding var selection: AppTab
    @ViewBuilder let content: (AppTab) -> Content

    var body: some View {
        TabView(selection: $selection) {
            ForEach([AppTab.groups, .group, .people, .settings], id: \.self) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab) {
                    content(tab)
                }
            }
        }
        .tint(Color("brand"))
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

extension EnvironmentValues {
    /// Set only by variant B: when present, Groups and Group show the toolbar "+".
    @Entry var prototypeAddExpense: (() -> Void)?
}

/// The one coloured control in the toolbar: prominent glass in Splitty Coral.
struct PrototypeToolbarAddButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(L10n.Tabs.addExpense, systemImage: "plus", action: action)
                .labelStyle(.iconOnly)
                .buttonStyle(.glassProminent)
                .tint(Color("brand"))
        }
    }
}
