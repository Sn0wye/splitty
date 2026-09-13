//
//  LanguageView.swift
//  Splitty
//

import SwiftUI

struct LanguageView: View {
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases) { language in
                    languageRow(language)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("background").ignoresSafeArea())
        .navigationTitle(Text(L10n.Language.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func languageRow(_ language: AppLanguage) -> some View {
        Button {
            guard languageManager.language != language else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                languageManager.language = language
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: language.icon)
                    .font(.body)
                    .foregroundStyle(Color("muted-foreground"))
                    .frame(width: 24)

                Text(language.displayName)
                    .foregroundStyle(Color("foreground"))

                Spacer()

                if languageManager.language == language {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color("foreground"))
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        LanguageView()
    }
}
