import SwiftUI

struct ExpenseCategoryPickerView: View {
    @Binding var selection: ExpenseCategory
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(ExpenseCategoryHeading.allCases) { heading in
                    let categories = matchingCategories(in: heading)
                    if !categories.isEmpty {
                        categorySection(heading, categories: categories)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.expenseBackground.ignoresSafeArea())
        .navigationTitle(L10n.Category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.expenseBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .searchable(text: $searchText)
    }

    private func categorySection(
        _ heading: ExpenseCategoryHeading,
        categories: [ExpenseCategory]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.expenseForeground.opacity(0.62))
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                    categoryRow(category)

                    if index < categories.count - 1 {
                        Divider()
                            .overlay(Color.expenseForeground.opacity(0.08))
                            .padding(.leading, 58)
                    }
                }
            }
            .background(
                Color.expenseForeground.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
    }

    private func categoryRow(_ category: ExpenseCategory) -> some View {
        Button {
            selection = category
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: category.glyph)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(category.tint, in: Circle())

                Text(category.name)
                    .foregroundStyle(Color.expenseForeground)

                Spacer()

                if selection == category {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.expenseForeground)
                }
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.98))
    }

    private func matchingCategories(in heading: ExpenseCategoryHeading) -> [ExpenseCategory] {
        guard !searchText.isEmpty else { return heading.categories }
        return heading.categories.filter { $0.name.localizedStandardContains(searchText) }
    }
}
