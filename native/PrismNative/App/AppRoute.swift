import Foundation

enum AppRoute: Hashable {
    case overview
    case history
    case rules
    case browsers
    case settings
}

enum MainWindowIdentity: String, Codable, Hashable {
    case main

    static let singleton = MainWindowIdentity.main
}
