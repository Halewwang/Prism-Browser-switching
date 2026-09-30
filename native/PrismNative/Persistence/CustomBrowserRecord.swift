import Foundation
import PrismCore
import SwiftData

@Model
final class CustomBrowserRecord {
    @Attribute(.unique) var id: String
    var bundleIdentifier: String
    var displayName: String
    var applicationURLString: String
    var securityScopedBookmark: Data?
    var selectorOrder: Int

    init(browser: BrowserDescriptor) {
        id = browser.id.rawValue
        bundleIdentifier = browser.bundleIdentifier
        displayName = browser.displayName
        applicationURLString = browser.applicationURL.absoluteString
        securityScopedBookmark = browser.securityScopedBookmark
        selectorOrder = browser.selectorOrder
    }

    func browserDescriptor() throws -> BrowserDescriptor {
        guard let applicationURL = URL(string: applicationURLString) else {
            throw PersistenceRecordError.invalidPayload
        }

        return BrowserDescriptor(
            id: BrowserID(rawValue: id),
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            applicationURL: applicationURL,
            securityScopedBookmark: securityScopedBookmark,
            origin: .custom,
            availability: .unavailable,
            selectorOrder: selectorOrder
        )
    }

    func replace(with browser: BrowserDescriptor) {
        bundleIdentifier = browser.bundleIdentifier
        displayName = browser.displayName
        applicationURLString = browser.applicationURL.absoluteString
        securityScopedBookmark = browser.securityScopedBookmark
        selectorOrder = browser.selectorOrder
    }
}

@Model
final class BrowserOrderRecord {
    @Attribute(.unique) var key: String
    var orderedIDsPayload: Data

    init(ids: [BrowserID]) throws {
        key = "primary"
        orderedIDsPayload = try JSONEncoder().encode(VersionedBrowserOrder(version: 1, ids: ids.map(\.rawValue)))
    }

    func browserIDs() throws -> [BrowserID] {
        let payload = try JSONDecoder().decode(VersionedBrowserOrder.self, from: orderedIDsPayload)
        guard payload.version == 1 else {
            throw PersistenceRecordError.invalidPayload
        }
        return payload.ids.map(BrowserID.init(rawValue:))
    }

    func replace(with ids: [BrowserID]) throws {
        let hidden = try hiddenBrowserIDs()
        orderedIDsPayload = try JSONEncoder().encode(VersionedBrowserOrder(version: 1, ids: ids.map(\.rawValue), hiddenIDs: hidden.map(\.rawValue)))
    }

    func hiddenBrowserIDs() throws -> [BrowserID] {
        let payload = try JSONDecoder().decode(VersionedBrowserOrder.self, from: orderedIDsPayload)
        guard payload.version == 1 else { throw PersistenceRecordError.invalidPayload }
        return (payload.hiddenIDs ?? []).map(BrowserID.init(rawValue:))
    }

    func replaceHiddenBrowserIDs(with ids: [BrowserID]) throws {
        let order = try browserIDs()
        orderedIDsPayload = try JSONEncoder().encode(VersionedBrowserOrder(version: 1, ids: order.map(\.rawValue), hiddenIDs: ids.map(\.rawValue)))
    }
}

private struct VersionedBrowserOrder: Codable {
    let version: Int
    let ids: [String]
    var hiddenIDs: [String]? = nil
}
