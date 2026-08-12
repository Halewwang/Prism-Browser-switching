import Observation
import PrismCore

@MainActor
@Observable
final class AppEnvironment {
    let route: AppRoute
    let unmatchedBehavior: UnmatchedBehavior
    let updateChecker: any UpdateChecking

    init(
        route: AppRoute,
        unmatchedBehavior: UnmatchedBehavior,
        updateChecker: any UpdateChecking
    ) {
        self.route = route
        self.unmatchedBehavior = unmatchedBehavior
        self.updateChecker = updateChecker
    }

    static let preview = AppEnvironment(
        route: .history,
        unmatchedBehavior: .alwaysAsk,
        updateChecker: DisabledUpdateChecker()
    )
}
