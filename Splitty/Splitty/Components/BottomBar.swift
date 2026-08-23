//
//  BottomBar.swift
//  Splitty
//

import SwiftUI

/// Flat, monochrome tab bar pinned to the bottom edge.
struct BottomBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                BottomBarItem(tab: tab, isSelected: tab == selection) {
                    selection = tab
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
        .padding(.horizontal, 8)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Color("background")
                Rectangle()
                    .fill(Color("border"))
                    .frame(height: 0.5)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct BottomBarItem: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.icon)
                .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Color("foreground") : Color("muted-foreground"))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

#Preview {
    StatefulPreviewWrapper(AppTab.groups) { binding in
        VStack {
            Spacer()
            BottomBar(selection: binding)
        }
        .background(Color("background"))
    }
}

/// Small helper so previews can drive a `@Binding`.
struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ value: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: value)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}
