//
//  BottomBar.swift
//  Splitty
//

import SwiftUI

/// Flat tab bar pinned to the bottom edge. The tabs stay monochrome so the add button, in
/// Splitty Coral, is the one thing on the bar with colour.
struct BottomBar: View {
    /// How far the add button rises above the bar's border, over the content.
    static let overhang: CGFloat = 18

    @Binding var selection: AppTab
    let isAdding: Bool
    let isAddEnabled: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab(.groups)
            tab(.group)
            addButton
            tab(.people)
            tab(.settings)
        }
        // Room above the labels so the icons don't sit against the border.
        .frame(height: 64, alignment: .bottom)
        .padding(.bottom, 4)
        .padding(.horizontal, 8)
        // Fill only from the border down: the strip above it, beside the raised add
        // button, stays clear so content scrolling under the bar shows through.
        .background(alignment: .top) {
            Color("background")
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color("border"))
                        .frame(height: 0.5)
                }
                .padding(.top, Self.overhang)
                .ignoresSafeArea(edges: .bottom)
        }
        // Selection, not impact: moving between tabs is a picker landing on a detent, and
        // the system has a texture for exactly that.
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func tab(_ tab: AppTab) -> some View {
        BottomBarItem(tab: tab, isSelected: tab == selection) {
            selection = tab
        }
        .padding(.top, Self.overhang)
    }

    private var addButton: some View {
        Button {
            onAdd()
        } label: {
            SwiftUI.Group {
                if isAdding {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(Color("brand"), in: Circle())
            .shadow(color: Color("brand").opacity(0.35), radius: 10, y: 4)
        }
        .frame(maxWidth: .infinity)
        // Lifted by what the bar grew, so the button keeps its overhang.
        .padding(.bottom, 4)
        .buttonStyle(.pressable(scale: 0.9))
        .disabled(isAdding || !isAddEnabled)
        .accessibilityLabel(L10n.Tabs.addExpense)
        .accessibilityIdentifier("app.addExpense")
    }
}

private struct BottomBarItem: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        // Labelled, like the system's own bar: an icon alone left two of the four tabs
        // to guesswork.
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .frame(height: 26)

                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(isSelected ? Color("foreground") : Color("muted-foreground"))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.92))
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

#Preview {
    StatefulPreviewWrapper(AppTab.groups) { binding in
        VStack {
            Spacer()
            BottomBar(selection: binding, isAdding: false, isAddEnabled: true) {}
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
