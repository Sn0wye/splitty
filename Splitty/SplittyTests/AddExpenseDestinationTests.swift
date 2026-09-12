import Testing
@testable import Splitty

struct AddExpenseDestinationTests {
    @Test func noGroupsOffersGroupCreation() {
        #expect(AddExpenseDestination.resolve(groups: [], currentGroupId: nil) == .createGroup)
    }

    @Test func oneGroupOpensItsExpenseSheet() {
        let group = makeGroup(id: 7)

        #expect(AddExpenseDestination.resolve(groups: [group], currentGroupId: nil) == .expense(group))
    }

    @Test func anOpenGroupWinsWhenSeveralGroupsExist() {
        let first = makeGroup(id: 7)
        let open = makeGroup(id: 9)

        #expect(AddExpenseDestination.resolve(groups: [first, open], currentGroupId: open.id) == .expense(open))
    }

    @Test func severalGroupsWithoutAnOpenGroupRequireAChoice() {
        let groups = [makeGroup(id: 7), makeGroup(id: 9)]

        #expect(AddExpenseDestination.resolve(groups: groups, currentGroupId: nil) == .chooseGroup(groups))
    }

    @Test func aStoredGroupThatIsNoLongerAvailableDoesNotOpen() {
        let groups = [makeGroup(id: 7), makeGroup(id: 9)]

        #expect(AddExpenseDestination.resolve(groups: groups, currentGroupId: 100) == .chooseGroup(groups))
    }

    private func makeGroup(id: Int) -> Group {
        Group(
            id: id,
            name: "Group \(id)",
            description: nil,
            netBalanceCents: 0,
            createdAt: "2026-01-01",
            members: []
        )
    }
}
