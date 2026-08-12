import Testing
@testable import PrismNative

@Test @MainActor func environmentStartsOnHistoryRoute() {
    let environment = AppEnvironment.preview
    #expect(environment.route == .history)
    #expect(environment.unmatchedBehavior == .alwaysAsk)
}

@Test @MainActor func disabledUpdateCheckerReportsThisBuildIsUnavailable() async {
    let checker = DisabledUpdateChecker()
    var events = checker.events.makeAsyncIterator()

    #expect(checker.canCheckForUpdates == false)
    checker.checkForUpdates()
    #expect(await events.next() == .failed(.unavailableInThisBuild))
}
