import Foundation
import Testing
@testable import PrismNative

@Suite("Sparkle release configuration")
struct SparkleUpdateConfigurationTests {
    @Test func requiresHTTPSFeedAndARealPublicKey() {
        #expect(!SparkleUpdateConfiguration(
            feedURL: URL(string: "http://updates.example.com/appcast.xml"),
            publicEDKey: "public-key"
        ).isReady)
        #expect(!SparkleUpdateConfiguration(
            feedURL: URL(string: "https://updates.example.com/appcast.xml"),
            publicEDKey: "$(SPARKLE_PUBLIC_ED_KEY)"
        ).isReady)
        #expect(SparkleUpdateConfiguration(
            feedURL: URL(string: "https://updates.example.com/appcast.xml"),
            publicEDKey: "public-key"
        ).isReady)
    }
}
