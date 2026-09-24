import SwiftUI

/// The first-run explanation and the choice between creating and joining a group.
/// Review mode uses the same screens but cannot write to the API or completion flag.
struct OnboardingView: View {
    private enum SetupSheet: String, Identifiable {
        case create
        case join

        var id: String { rawValue }
    }

    let onFinish: (Int?) -> Void
    private let isReview: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingChoices: Bool
    @State private var illustrationStep: Int
    @State private var setupSheet: SetupSheet?

    init(
        isReview: Bool = false,
        startsWithChoices: Bool = false,
        onFinish: @escaping (Int?) -> Void
    ) {
        self.isReview = isReview
        self.onFinish = onFinish
        _showingChoices = State(initialValue: startsWithChoices)
        _illustrationStep = State(initialValue: startsWithChoices ? 2 : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(showingChoices ? L10n.Onboarding.setupTitle : L10n.Onboarding.title)
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color("foreground"))
                            .fixedSize(horizontal: false, vertical: true)

                        Text(showingChoices ? L10n.Onboarding.setupDetail : L10n.Onboarding.detail)
                            .font(.subheadline)
                            .foregroundStyle(Color("muted-foreground"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 44)

                    SplitIllustration(step: illustrationStep)
                        .padding(.top, 56)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.Onboarding.illustration)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)

            actions
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
        .background(Color("background").ignoresSafeArea())
        .task { await animateIllustration() }
        .sheet(item: $setupSheet) { sheet in
            switch sheet {
            case .create:
                GroupFormSheet(isReview: isReview) { onFinish($0) }
            case .join:
                JoinGroupSheet(isReview: isReview) { onFinish($0.id) }
            }
        }
    }

    private var header: some View {
        HStack {
            if showingChoices {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        showingChoices = false
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 32, height: 32, alignment: .leading)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(L10n.Common.back)
            } else {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            }

            Spacer()

            Button(isReview ? L10n.Common.done : L10n.Onboarding.skip) {
                onFinish(nil)
            }
            .font(.subheadline)
            .foregroundStyle(Color("muted-foreground"))
        }
        .foregroundStyle(Color("foreground"))
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if showingChoices {
                PrimaryButton(title: L10n.Onboarding.createGroup) {
                    setupSheet = .create
                }
                OnboardingSecondaryButton(title: L10n.Onboarding.joinGroup) {
                    setupSheet = .join
                }
            } else {
                PrimaryButton(title: L10n.Onboarding.continueButton) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        showingChoices = true
                        illustrationStep = 2
                    }
                }
            }
        }
    }

    private func animateIllustration() async {
        guard illustrationStep == 0 else { return }
        guard !reduceMotion else {
            illustrationStep = 2
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.3)) { illustrationStep = 1 }
            try await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeOut(duration: 0.3)) { illustrationStep = 2 }
        } catch {}
    }
}

struct OnboardingSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(Color("foreground"))
                .overlay(Capsule().strokeBorder(Color("border"), lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}

private struct SplitIllustration: View {
    let step: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color("category-food"), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Onboarding.exampleExpense)
                        .font(.headline)
                    Text(L10n.Onboarding.examplePayer)
                        .font(.subheadline)
                        .foregroundStyle(Color("muted-foreground"))
                }
                Spacer(minLength: 8)
                Text("$30.00")
                    .font(.headline.monospacedDigit())
            }
            .padding(20)

            Divider().padding(.horizontal, 20)

            HStack(spacing: 12) {
                share(L10n.Common.you, amount: "$15.00")
                share(L10n.Common.someone, amount: "$15.00")
            }
            .padding(20)
            .opacity(step >= 1 ? 1 : 0)
            .offset(y: step >= 1 ? 0 : 8)

            Divider().padding(.horizontal, 20)

            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.semibold))
                Text(L10n.Onboarding.exampleResult)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(Color("foreground"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .opacity(step >= 2 ? 1 : 0)
        }
        .foregroundStyle(Color("card-foreground"))
        .background(Color("card"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func share(_ name: String, amount: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title3)
                .foregroundStyle(Color("muted-foreground"))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.caption).foregroundStyle(Color("muted-foreground"))
                Text(amount).font(.subheadline.weight(.semibold).monospacedDigit())
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
