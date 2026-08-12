import Foundation

enum AppRoute: Hashable {
    case history
    case rules
    case browsers
}

enum MainWindowIdentity: String, Codable, Hashable {
    case main

    static let singleton = MainWindowIdentity.main
}
