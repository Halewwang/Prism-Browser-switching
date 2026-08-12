import Foundation

enum AppRoute: Hashable {
    case history
}

enum MainWindowIdentity: String, Codable, Hashable {
    case main

    static let singleton = MainWindowIdentity.main
}
