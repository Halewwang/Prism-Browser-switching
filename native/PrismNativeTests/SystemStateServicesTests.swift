import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Test @MainActor func readingDefaultStatusNeverSetsAHandler() async throws {
    let client = StubDefaultHandlerClient(http: "com.example.other", https: nil)
    let service = DefaultBrowserService(
        client: client,
        applicationURL: URL(fileURLWithPath: "/Applications/Prism.app"),
        bundleIdentifier: "com.prism.app"
    )

    let state = try await service.status()

    #expect(state == .inactive(http: false, https: false))
    #expect(client.setCalls.isEmpty)
}

@Test @MainActor func defaultStatusReportsEachSchemeFromTheRealHandlerIdentifier() async throws {
    let client = StubDefaultHandlerClient(http: "com.prism.app", https: "com.example.other")
    let service = DefaultBrowserService(
        client: client,
        applicationURL: URL(fileURLWithPath: "/Applications/Prism.app"),
        bundleIdentifier: "com.prism.app"
    )

    #expect(try await service.status() == .inactive(http: true, https: false))
    #expect(client.queriedSchemes == ["http", "https"])
    #expect(client.setCalls.isEmpty)
}

@Test @MainActor func defaultStatusCoversAllHTTPAndHTTPSHandlerCombinations() async throws {
    let cases: [(http: String?, https: String?, expected: DefaultHandlerState)] = [
        (nil, nil, .inactive(http: false, https: false)),
        ("com.prism.app", nil, .inactive(http: true, https: false)),
        (nil, "com.prism.app", .inactive(http: false, https: true)),
        ("com.prism.app", "com.prism.app", .active)
    ]

    for value in cases {
        let client = StubDefaultHandlerClient(http: value.http, https: value.https)
        let service = DefaultBrowserService(
            client: client,
            applicationURL: URL(fileURLWithPath: "/Applications/Prism.app"),
            bundleIdentifier: "com.prism.app"
        )

        #expect(try await service.status() == value.expected)
        #expect(client.queriedSchemes == ["http", "https"])
        #expect(client.setCalls.isEmpty)
    }
}

@Test @MainActor func confirmedDefaultChangeWaitsForBothSchemesAndRequeriesTruth() async throws {
    let client = StubDefaultHandlerClient(http: nil, https: nil)
    let service = DefaultBrowserService(
        client: client,
        applicationURL: URL(fileURLWithPath: "/Applications/Prism.app"),
        bundleIdentifier: "com.prism.app"
    )

    let state = try await service.setAsDefaultAfterUserConfirmation()

    #expect(state == .active)
    #expect(client.setCalls.map(\.scheme) == ["http", "https"])
    #expect(client.setCalls.allSatisfy { $0.applicationURL.path == "/Applications/Prism.app" })
    #expect(client.queriedSchemes == ["http", "https"])
}

@Test @MainActor func partialDefaultChangeReturnsRealStateAndTypedFailure() async {
    let client = StubDefaultHandlerClient(http: nil, https: nil, failingSchemes: ["https"])
    let service = DefaultBrowserService(
        client: client,
        applicationURL: URL(fileURLWithPath: "/Applications/Prism.app"),
        bundleIdentifier: "com.prism.app"
    )

    do {
        _ = try await service.setAsDefaultAfterUserConfirmation()
        Issue.record("Expected a partial default-handler failure")
    } catch let error as DefaultBrowserServiceError {
        #expect(error == .incomplete(
            state: .inactive(http: true, https: false),
            failedSchemes: ["https"]
        ))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(client.setCalls.map(\.scheme) == ["http", "https"])
    #expect(client.queriedSchemes == ["http", "https"])
}

@Test @MainActor func setterSuccessIsNotReportedActiveWhenRequeryStillDisagrees() async {
    let client = StubDefaultHandlerClient(
        http: nil,
        https: nil,
        appliesSuccessfulChanges: false
    )
    let service = DefaultBrowserService(
        client: client,
        applicationURL: URL(fileURLWithPath: "/Applications/Prism.app"),
        bundleIdentifier: "com.prism.app"
    )

    do {
        _ = try await service.setAsDefaultAfterUserConfirmation()
        Issue.record("A completed setter call must not replace the real handler status")
    } catch let error as DefaultBrowserServiceError {
        #expect(error == .incomplete(
            state: .inactive(http: false, https: false),
            failedSchemes: []
        ))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test(arguments: [
    (LoginItemClientStatus.notRegistered, LoginItemState.notRegistered),
    (.enabled, .enabled),
    (.requiresApproval, .requiresApproval),
    (.notFound, .notFound)
])
@MainActor func loginItemStatusMapsEverySystemState(
    clientStatus: LoginItemClientStatus,
    expected: LoginItemState
) {
    let client = StubLoginItemClient(status: clientStatus)
    let service = LoginItemService(client: client)

    #expect(service.status() == expected)
    #expect(client.registerCount == 0)
    #expect(client.unregisterCount == 0)
    #expect(client.openSettingsCount == 0)
}

@Test @MainActor func loginItemMutationsRunOnlyFromExplicitActions() throws {
    let client = StubLoginItemClient(status: .notRegistered)
    let service = LoginItemService(client: client)

    _ = service.status()
    #expect(client.registerCount == 0)
    #expect(client.unregisterCount == 0)

    try service.registerAfterUserAction()
    try service.unregisterAfterUserAction()

    #expect(client.registerCount == 1)
    #expect(client.unregisterCount == 1)
}

@Test @MainActor func requiresApprovalActionOpensLoginItemsSettingsWithoutRegistering() {
    let client = StubLoginItemClient(status: .requiresApproval)
    let service = LoginItemService(client: client)

    service.openApprovalSettingsAfterUserAction()

    #expect(client.openSettingsCount == 1)
    #expect(client.registerCount == 0)
    #expect(client.unregisterCount == 0)
}

@MainActor
private final class StubDefaultHandlerClient: DefaultHandlerClient {
    struct SetCall: Equatable {
        let applicationURL: URL
        let scheme: String
    }

    private var handlers: [String: String]
    private let failingSchemes: Set<String>
    private let appliesSuccessfulChanges: Bool
    private(set) var queriedSchemes: [String] = []
    private(set) var setCalls: [SetCall] = []

    init(
        http: String?,
        https: String?,
        failingSchemes: Set<String> = [],
        appliesSuccessfulChanges: Bool = true
    ) {
        handlers = ["http": http, "https": https].compactMapValues { $0 }
        self.failingSchemes = failingSchemes
        self.appliesSuccessfulChanges = appliesSuccessfulChanges
    }

    func handlerBundleIdentifier(forScheme scheme: String) -> String? {
        queriedSchemes.append(scheme)
        return handlers[scheme]
    }

    func setDefault(applicationURL: URL, forScheme scheme: String) async throws {
        setCalls.append(SetCall(applicationURL: applicationURL, scheme: scheme))
        guard !failingSchemes.contains(scheme) else {
            throw StubSystemStateError.rejected
        }
        if appliesSuccessfulChanges {
            handlers[scheme] = "com.prism.app"
        }
    }
}

@MainActor
private final class StubLoginItemClient: LoginItemClient {
    var clientStatus: LoginItemClientStatus
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSettingsCount = 0

    init(status: LoginItemClientStatus) {
        clientStatus = status
    }

    func status() -> LoginItemClientStatus {
        clientStatus
    }

    func register() throws {
        registerCount += 1
    }

    func unregister() throws {
        unregisterCount += 1
    }

    func openSystemSettingsLoginItems() {
        openSettingsCount += 1
    }
}

private enum StubSystemStateError: Error {
    case rejected
}
