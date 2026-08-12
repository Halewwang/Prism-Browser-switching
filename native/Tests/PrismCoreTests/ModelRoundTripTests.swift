import Foundation
import Testing
@testable import PrismCore

@Test func routingRuleRoundTripsWithoutLosingPriority() throws {
    let rule = RoutingRule(
        id: UUID(uuidString: "2A50BE99-7BA5-4F41-9B8C-1849D704B631")!,
        isEnabled: true,
        matcher: .hostAndSubdomains("company.com"),
        targetBrowserID: BrowserID("com.apple.Safari"),
        priority: 3,
        label: "Company links",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2)
    )

    let data = try JSONEncoder().encode(rule)
    let decoded = try JSONDecoder().decode(RoutingRule.self, from: data)

    #expect(decoded == rule)
    #expect(decoded.priority == 3)
}
