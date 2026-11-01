import Testing
@testable import Splitty

struct GroupRecencyTests {
    @Test func newestActivityComesFirst() {
        let groups = [
            makeGroup(id: 1, activity: "2026-03-01T12:00:00Z"),
            makeGroup(id: 2, activity: "2026-05-01T12:00:00Z"),
            makeGroup(id: 3, activity: "2026-04-01T12:00:00.123Z"),
        ]

        #expect(ids(Group.recentFirst(groups, recentlyOpened: [1])) == [2, 3, 1])
    }

    @Test func aGroupWithActivityOutranksOneOnlyOpened() {
        let groups = [
            makeGroup(id: 1, activity: nil),
            makeGroup(id: 2, activity: "2025-01-01T12:00:00Z"),
        ]

        #expect(ids(Group.recentFirst(groups, recentlyOpened: [1])) == [2, 1])
    }

    @Test func withoutActivityTheMostRecentlyOpenedComesFirst() {
        let groups = [makeGroup(id: 1), makeGroup(id: 2), makeGroup(id: 3)]

        #expect(ids(Group.recentFirst(groups, recentlyOpened: [3, 1])) == [3, 1, 2])
    }

    @Test func otherwiseTheNewestGroupComesFirst() {
        let groups = [
            makeGroup(id: 1, createdAt: "2026-01-01T12:00:00Z"),
            makeGroup(id: 2, createdAt: "2026-02-01T12:00:00Z"),
        ]

        #expect(ids(Group.recentFirst(groups, recentlyOpened: [])) == [2, 1])
    }

    @Test func groupsAlikeOnEveryKeyKeepTheirOrder() {
        let groups = [makeGroup(id: 9), makeGroup(id: 7), makeGroup(id: 8)]

        #expect(ids(Group.recentFirst(groups, recentlyOpened: [])) == [9, 7, 8])
    }

    @Test func theChoiceSheetListsGroupsRecentFirst() {
        let groups = [
            makeGroup(id: 1, activity: "2026-03-01T12:00:00Z"),
            makeGroup(id: 2, activity: "2026-05-01T12:00:00Z"),
        ]

        let destination = AddExpenseDestination.resolve(groups: groups, currentGroupId: nil)

        #expect(destination == .chooseGroup([groups[1], groups[0]]))
    }

    private func ids(_ groups: [Group]) -> [Int] { groups.map(\.id) }

    private func makeGroup(
        id: Int,
        activity: String? = nil,
        createdAt: String = "2026-01-01T12:00:00Z"
    ) -> Group {
        Group(
            id: id,
            name: "Group \(id)",
            description: nil,
            netBalanceCents: 0,
            createdAt: createdAt,
            members: [],
            lastActivityAt: activity
        )
    }
}
