import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Suite("Rule editor pending navigation")
@MainActor
struct RuleEditorIntentTests {
    @Test func activeDraftKeepsPendingNavigationUntilDismissalThenConsumesExactlyOnce() throws {
        let coordinator = RuleEditorIntentCoordinator()
        let originalPrefill = SelectorRulePrefill.domain(host: "original.example", browserID: "old")
        let original = try #require(coordinator.beginPresentation { originalPrefill })
        var pending: SelectorRulePrefill? = .domain(host: "queued.example", browserID: "new")
        var consumeCount = 0
        func consume() -> SelectorRulePrefill? {
            consumeCount += 1
            defer { pending = nil }
            return pending
        }

        #expect(coordinator.beginPresentation(takePending: consume) == nil)
        #expect(consumeCount == 0)
        #expect(pending == .domain(host: "queued.example", browserID: "new"))
        #expect(original.prefill == originalPrefill)
        #expect(coordinator.activePresentationID == original.id)

        #expect(coordinator.finishDismissal(id: original.id))
        let resumed = try #require(coordinator.beginPresentation(takePending: consume))
        #expect(resumed.prefill == .domain(host: "queued.example", browserID: "new"))
        #expect(consumeCount == 1)
        #expect(pending == nil)
        #expect(coordinator.beginPresentation(takePending: consume) == nil)
        #expect(consumeCount == 1)
    }

    @Test func staleOrRepeatedDismissalCannotReleaseANewerDraft() throws {
        let coordinator = RuleEditorIntentCoordinator()
        let old = try #require(coordinator.beginPresentation { nil })
        #expect(coordinator.finishDismissal(id: old.id))
        let current = try #require(coordinator.beginPresentation { .savedRule(id: UUID()) })
        #expect(!coordinator.finishDismissal(id: old.id))
        #expect(coordinator.activePresentationID == current.id)
        #expect(coordinator.beginPresentation { nil } == nil)
        #expect(coordinator.finishDismissal(id: current.id))
        #expect(!coordinator.finishDismissal(id: current.id))
    }
}
