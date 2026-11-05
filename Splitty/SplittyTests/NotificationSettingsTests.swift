//
//  NotificationSettingsTests.swift
//  SplittyTests
//

import Foundation
import Testing
@testable import Splitty

struct NotificationSettingsTests {
    @Test func switchingAKindOffAndOnLeavesTheOthersAsTheyWere() {
        let settings = NotificationSettings(enabled: true, muted: [.expenseChanged])

        let off = settings.setting(.paymentReminder, on: false)
        let backOn = off.setting(.expenseChanged, on: true)

        #expect(off.muted == [.expenseChanged, .paymentReminder])
        #expect(backOn.muted == [.paymentReminder])
        #expect(backOn.enabled)
    }

    @Test func theBodyUsesTheServersNames() throws {
        let body = NotificationSettings(enabled: false, muted: [.removedFromGroup]).body

        #expect(body["enabled"] as? Bool == false)
        #expect(body["muted"] as? [String] == ["removed_from_group"])
    }

    @Test func everyKindBelongsToExactlyOneSection() {
        let grouped = NotificationKind.Section.allCases.flatMap(\.kinds)

        #expect(grouped.count == NotificationKind.allCases.count)
        #expect(Set(grouped) == Set(NotificationKind.allCases))
    }

    @Test func aPushNamesItsGroupAsAnIntOrANumber() {
        #expect(PushNotifications.groupId(in: ["groupId": 7]) == 7)
        #expect(PushNotifications.groupId(in: ["groupId": NSNumber(value: 9)]) == 9)
        #expect(PushNotifications.groupId(in: [:]) == nil)
    }
}
