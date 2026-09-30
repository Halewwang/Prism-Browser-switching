import Foundation
import PrismCore

enum RulePreviewError: Error, Equatable { case invalidURL }

struct RulePreviewResult {
    let source: SourceApplication
    let decision: RoutingDecision
    let matchingRule: RoutingRule?
}

/// Uses the production routing engine and has no launcher, queue or persistence side effects.
enum RulePreview {
    static func evaluate(
        urlText: String,
        source: SourceApplication,
        rules: [RoutingRule],
        availableBrowserIDs: Set<BrowserID>,
        settings: AppSettings
    ) throws -> RulePreviewResult {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
              BootstrapLinkBuffer.accepts(url),
              let host = url.host, !host.isEmpty
        else { throw RulePreviewError.invalidURL }
        let request = LinkRequest(id: UUID(), url: url, receivedAt: .now, source: source)
        let engine = RuleEngine()
        let decision = engine.decide(
            request: request,
            rules: rules,
            availableBrowserIDs: availableBrowserIDs,
            eligibleSourceBundleIDs: [],
            settings: settings
        )
        let matchingRule = engine.matchingRule(request: request, rules: rules, settings: settings)
        return RulePreviewResult(source: source, decision: decision, matchingRule: matchingRule)
    }
}
