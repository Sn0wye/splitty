import Testing
@testable import Splitty

struct PerformanceSignpostTests {

    // These names are the Instruments contract. Renaming one silently breaks a saved
    // template, so they are pinned rather than derived.
    @Test(arguments: [
        (PerformanceSignpost.Interval.launch, "Launch"),
        (.groupsScroll, "GroupsScroll"),
        (.timelineScroll, "TimelineScroll"),
        (.amountEntry, "AmountEntry"),
        (.swipeRelease, "SwipeRelease"),
        (.splitEdit, "SplitEdit"),
    ])
    func intervalNamesStayStable(
        interval: PerformanceSignpost.Interval,
        name: String
    ) {
        #expect(interval.rawValue == name)
    }

    @Test func aroundRunsTheWorkEvenWhenTheIntervalIsEmpty() {
        var ran = false
        let value = PerformanceSignpost.around(.amountEntry) {
            ran = true
            return 21
        }
        #expect(ran)
        #expect(value == 21)
    }
}
