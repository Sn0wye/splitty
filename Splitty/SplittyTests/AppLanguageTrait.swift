import Testing
@testable import Splitty

/// Pins the app language for a suite or test, so copy assertions read the language they
/// name instead of whatever the simulator was last left in.
///
/// The pin is task-local: suites running in parallel each see their own language, and
/// nothing is written to the preference the app and the simulator share.
struct AppLanguageTrait: SuiteTrait, TestTrait, TestScoping {
    let language: AppLanguage

    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await AppLanguage.$pinned.withValue(language) {
            try await function()
        }
    }
}

extension Trait where Self == AppLanguageTrait {
    static func appLanguage(_ language: AppLanguage) -> Self {
        AppLanguageTrait(language: language)
    }
}
