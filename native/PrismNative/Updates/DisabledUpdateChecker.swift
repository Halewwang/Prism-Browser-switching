import Foundation

@MainActor
final class DisabledUpdateChecker: UpdateChecking {
    let events: AsyncStream<UpdateEvent>
    private let continuation: AsyncStream<UpdateEvent>.Continuation

    let canCheckForUpdates = false
    var automaticallyChecksForUpdates = false

    init() {
        var streamContinuation: AsyncStream<UpdateEvent>.Continuation?
        events = AsyncStream { streamContinuation = $0 }
        continuation = streamContinuation!
    }

    func checkForUpdates() {
        continuation.yield(.failed(.unavailableInThisBuild))
    }
}
