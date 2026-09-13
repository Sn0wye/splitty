import SwiftUI

struct ExpenseCategoryPickerView: View {
    @Binding var selection: ExpenseCategory
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        List {
            ForEach(ExpenseCategoryHeading.allCases) { heading in
                let categories = matchingCategories(in: heading)
                if !categories.isEmpty {
                    Section(heading.title) {
                        ForEach(categories) { category in
                            Button {
                                selection = category
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: category.glyph)
                                        .foregroundStyle(.white)
                                        .frame(width: 30, height: 30)
                                        .background(category.tint, in: Circle())

                                    Text(category.name)
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    if selection == category {
                                        Image(systemName: "checkmark")
                                            .fontWeight(.semibold)
                                            .foregroundStyle(category.tint)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.Expense.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText)
    }

    private func matchingCategories(in heading: ExpenseCategoryHeading) -> [ExpenseCategory] {
        guard !searchText.isEmpty else { return heading.categories }
        return heading.categories.filter { $0.name.localizedStandardContains(searchText) }
    }
}
