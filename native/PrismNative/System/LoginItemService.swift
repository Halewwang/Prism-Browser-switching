import Foundation
import ServiceManagement

enum LoginItemClientStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

enum LoginItemState: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

@MainActor
protocol LoginItemClient: AnyObject {
    func status() -> LoginItemClientStatus
    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

@MainActor
final class LoginItemService {
    private let client: any LoginItemClient

    init(client: any LoginItemClient = SystemLoginItemClient()) {
        self.client = client
    }

    func status() -> LoginItemState {
        switch client.status() {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        }
    }

    func registerAfterUserAction() throws {
        try client.register()
    }

    func unregisterAfterUserAction() throws {
        try client.unregister()
    }

    func openApprovalSettingsAfterUserAction() {
        client.openSystemSettingsLoginItems()
    }
}

@MainActor
final class SystemLoginItemClient: LoginItemClient {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    func status() -> LoginItemClientStatus {
        switch service.status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
