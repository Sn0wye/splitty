import Foundation
import Testing
@testable import Splitty

struct PerformanceScenariosTests {

    @Test func buildsOneHundredGroupsWithStableIdentities() {
        let groups = PerformanceScenarios.groups
        #expect(groups.count == 100)
        #expect(groups.map(\.id) == Array(1...100))
        #expect(groups.map(\.name) == (1...100).map { "Group \($0)" })
        #expect(PerformanceScenarios.groups.map(\.id) == groups.map(\.id))
    }

    @Test func buildsAFiveHundredExpenseTimelineThatGroupsByDate() {
        let expenses = PerformanceScenarios.timeline
        #expect(expenses.count == 500)
        #expect(expenses.map(\.id) == Array(1...500))

        let grouped = Expense.groupExpensesByDate(expenses)
        #expect(grouped.flatMap(\.expenses).count == 500)
        #expect(grouped.map(\.date) == grouped.map(\.date).sorted(by: >))
    }

    @Test func largeAvatarSourcesAreDeterministicAndHighResolution() {
        let urls = PerformanceScenarios.largeAvatarURLs
        #expect(urls.count == 8)
        #expect(Set(urls).count == 8)
        #expect(urls.allSatisfy { $0.absoluteString.contains("/1024/1024") })
        #expect(PerformanceScenarios.largeAvatarURLs == urls)
    }

    @Test func aFiftyMemberSplitDividesATotalExactly() {
        let members = PerformanceScenarios.splitMembers
        #expect(members.count == 50)
        #expect(members.map(\.userId) == Array(1...50))

        let configuration = SplitConfiguration(
            payerId: 1,
            mode: .equal(participants: Set(members.map(\.userId)))
        )
        let amounts = configuration.amounts(totalCents: 10_000)
        #expect(amounts.count == 50)
        #expect(amounts.values.reduce(0, +) == 10_000)
    }
}
