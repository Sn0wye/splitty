import Testing
@testable import Splitty

struct LeaveCopyTests {
    @Test func lastMemberSeesPermanentDeletionWarning() {
        let copy = LeaveCopy(memberCount: 1, groupName: "Weekend away")

        #expect(copy.title == "Leave and delete \"Weekend away\"?")
        #expect(copy.message == "The group and all of its expenses are deleted permanently.")
        #expect(copy.confirmationLabel == "Leave and delete")
    }

    @Test(arguments: [2, 8])
    func groupMemberCanSeeHowToRejoin(memberCount: Int) {
        let copy = LeaveCopy(memberCount: memberCount, groupName: "Weekend away")

        #expect(copy.title == "Leave \"Weekend away\"?")
        #expect(copy.message == "You will lose access to this group's expenses. You can re-join with a new invite code.")
        #expect(copy.confirmationLabel == "Leave")
    }

    @Test(arguments: ["", "Friends / Family 🥳"])
    func everyGroupNameProducesReadableCopy(groupName: String) {
        let copy = LeaveCopy(memberCount: 2, groupName: groupName)

        #expect(copy.title == (groupName.isEmpty ? "Leave this group?" : "Leave \"\(groupName)\"?"))
        #expect(!copy.message.isEmpty)
        #expect(copy.confirmationLabel == "Leave")
    }

    @Test func trimsWhitespaceAroundTheGroupName() {
        let copy = LeaveCopy(memberCount: 2, groupName: "  Weekend away  ")

        #expect(copy.title == "Leave \"Weekend away\"?")
    }
}
