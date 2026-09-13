//
//  BottomBar.swift
//  Splitty
//

import SwiftUI

/// Flat, monochrome tab bar pinned to the bottom edge.
struct BottomBar: View {
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
        .frame(height: 60, alignment: .bottom)
        .padding(.bottom, 4)
        .padding(.horizontal, 8)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Color("background")
                Rectangle()
                    .fill(Color("border"))
                    .frame(height: 0.5)
                    .padding(.top, 18)
            }
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
        .padding(.top, 18)
    }

    private var addButton: some View {
        Button {
            onAdd()
        } label: {
            SwiftUI.Group {
                if isAdding {
                    ProgressView()
                        .tint(Color("background"))
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                }
            }
            .foregroundStyle(Color("background"))
            .frame(width: 56, height: 56)
            .background(Color("foreground"), in: Circle())
            .shadow(radius: 8, y: 4)
        }
        .frame(maxWidth: .infinity)
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
        Button(action: action) {
            Image(systemName: tab.icon)
                .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Color("foreground") : Color("muted-foreground"))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.88))
        .accessibilityLabel(tab.title)
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
