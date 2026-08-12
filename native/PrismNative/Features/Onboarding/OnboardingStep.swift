enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome
    case linkHandling
    case browsers
    case testLink
}

enum OnboardingAlert: Equatable {
    case defaultHandlerIncomplete
    case defaultHandlerUnavailable
    case noUsableBrowser
    case browserScanFailed
    case customBrowserFailed
    case settingsNotSaved
    case testLinkFailed
    case testLinkCancellationFailed
}
