import Foundation

enum UpdateFailure: Equatable, Sendable {
    case unavailableInThisBuild
    case configuration
    case network
    case signatureVerification
    case installation
    case system(String)
}

enum UpdateEvent: Equatable, Sendable {
    case checking
    case current
    case available(version: String)
    case downloading(progress: Double?)
    case extracting(progress: Double?)
    case readyToInstall
    case installed(relaunched: Bool)
    case cancelled
    case failed(UpdateFailure)
}

@MainActor
protocol UpdateChecking: AnyObject {
    var events: AsyncStream<UpdateEvent> { get }
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    func checkForUpdates()
}
