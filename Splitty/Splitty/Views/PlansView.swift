//
//  PlansView.swift
//  Splitty
//

import SwiftUI

/// What a group has committed to, one section each. Installments, the group's active
/// recurring expenses, is the first. Holds no scroll view of its own, so it sits under the
/// group screen's header today and can move elsewhere later. Reloads every time it appears.
struct PlansView: View {
    @ObservedObject var viewModel: PlansViewModel
    /// Opens a recurring expense where a member edits or stops it: its newest expense.
    let onOpenPlan: (RecurringPlan) -> Void

    var body: some View {
        VStack(spacing: 0) {
            InstallmentsSection(state: viewModel.installments, onOpenPlan: onOpenPlan) {
                Task { await viewModel.load() }
            }
        }
        .task { await viewModel.load() }
    }
}

private struct InstallmentsSection: View {
    let state: PlansViewModel.InstallmentsState
    let onOpenPlan: (RecurringPlan) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TimelineDateHeader(title: L10n.Plans.installments)

            switch state {
            case .loading:
                SplittyLoader(size: 32)
                    .frame(maxWidth: .infinity)
                    .padding(32)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 12) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Button(action: onRetry) { Text(L10n.Common.tryAgain) }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            case .empty:
                EmptyStateView(
                    symbol: "repeat",
                    title: L10n.Plans.noInstallments,
                    detail: L10n.Plans.noInstallmentsDetail
                ) {}
                .padding(.bottom, 32)
            case .loaded(let plans):
                ForEach(plans) { plan in
                    Button { onOpenPlan(plan) } label: {
                        RecurringPlanRow(plan: plan)
                    }
                    .buttonStyle(.pressable(scale: 0.98))
                    .accessibilityIdentifier("plans.installment.\(plan.id)")
                }
            }
        }
        .background(Color("card"))
        .clipShape(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
        )
    }
}

/// A recurring expense: what it is, how often, and how far along.
struct RecurringPlanRow: View {
    @Environment(\.currency) private var currency
    let plan: RecurringPlan

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(plan.category.tint)
                    .frame(width: 40, height: 40)
                CategoryGlyph(category: plan.category)
                    .font(.system(size: 18))
                    .foregroundColor(.white)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.description)
                    .font(.headline)
                    .foregroundColor(Color("card-foreground"))
                    .multilineTextAlignment(.leading)

                if let badge = plan.frequency?.badge {
                    RepeatBadge(text: badge)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(Money.formatted(amount: plan.amount, currency: currency))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(Color("card-foreground"))
                Text(plan.progressText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(Color("muted-foreground"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color("card"))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color("border")),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
