import SwiftUI

struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let title: String
    let detail: String
    let actions: Actions

    init(
        symbol: String,
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color("foreground"))
                .padding(.bottom, 6)

            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color("foreground"))
                .multilineTextAlignment(.center)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Color("muted-foreground"))
                .multilineTextAlignment(.center)

            VStack(spacing: 14) {
                actions
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 44)
    }
}
