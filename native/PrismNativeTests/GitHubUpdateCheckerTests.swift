import Foundation
import Testing
@testable import PrismNative

@Suite("GitHub native updates")
struct GitHubUpdateCheckerTests {
    @Test func selectsTheNewestNativeReleaseIncludingPublicTests() throws {
        let payload = Data("""
        [
          {"tag_name":"v1.10.22","draft":false,"body":"Electron", "assets":[
            {"name":"Prism-1.10.22-arm64.dmg","browser_download_url":"https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.10.22/Prism-1.10.22-arm64.dmg"}]},
          {"tag_name":"v1.12.0","draft":false,"prerelease":true,"body":"Native test", "assets":[
            {"name":"Prism-1.12.0-universal-test.dmg","browser_download_url":"https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.12.0/Prism-1.12.0-universal-test.dmg"}]},
          {"tag_name":"v1.13.0","draft":true,"assets":[
            {"name":"Prism-1.13.0.dmg","browser_download_url":"https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.13.0/Prism-1.13.0.dmg"}]},
          {"tag_name":"v1.11.0","draft":false,"assets":[
            {"name":"Prism-1.11.0.dmg","browser_download_url":"https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.11.0/Prism-1.11.0.dmg"}]}
        ]
        """.utf8)
        let installer = try GitHubPublishedInstallerLookup.decode(payload)
        #expect(installer.version == "1.12.0")
        #expect(installer.notes == "Native test")
        #expect(installer.isPrerelease)
    }

    @Test func discoversSignedAssetsOnlyFromTheSameExactRelease() throws {
        let base = "https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.15.0/"
        let payload = Data("""
        [{"tag_name":"v1.15.0","draft":false,"assets":[
          {"name":"Prism-1.15.0-universal-test.dmg","size":12345,"browser_download_url":"\(base)Prism-1.15.0-universal-test.dmg"},
          {"name":"update-manifest.json","browser_download_url":"\(base)update-manifest.json"},
          {"name":"update-manifest.sig","browser_download_url":"\(base)update-manifest.sig"}]}]
        """.utf8)
        let installer = try GitHubPublishedInstallerLookup.decode(payload)
        #expect(installer.manifestURL == URL(string: base + "update-manifest.json"))
        #expect(installer.signatureURL == URL(string: base + "update-manifest.sig"))
        #expect(installer.fileByteCount == 12345)
        let forged = Data(String(decoding: payload, as: UTF8.self)
            .replacingOccurrences(of: "\(base)update-manifest.sig", with: "https://evil.example/update-manifest.sig").utf8)
        #expect(try GitHubPublishedInstallerLookup.decode(forged).signatureURL == nil)
    }

    @Test func rejectsLegacyMalformedAndUntrustedDownloads() {
        for (tag, asset, url) in [
            ("v1.10.22", "Prism-1.10.22-universal.dmg", "https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.10.22/Prism-1.10.22-universal.dmg"),
            ("v1.12.0-beta", "Prism-1.12.0-beta.dmg", "https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.12.0-beta/Prism-1.12.0-beta.dmg"),
            ("v1.12.0", "Prism-1.12.0-arm64.dmg", "https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.12.0/Prism-1.12.0-arm64.dmg"),
            ("v1.12.0", "Prism-1.12.0.dmg", "http://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.12.0/Prism-1.12.0.dmg"),
            ("v1.12.0", "Prism-1.12.0.dmg", "https://example.com/Prism-1.12.0.dmg")
        ] {
            let payload = Data("""
            [{"tag_name":"\(tag)","draft":false,"assets":[{"name":"\(asset)","browser_download_url":"\(url)"}]}]
            """.utf8)
            #expect(throws: GitHubPublishedInstallerError.noCompatibleRelease) {
                try GitHubPublishedInstallerLookup.decode(payload)
            }
        }
    }

    @Test func comparesVersionNumbersWithoutLexicalOrderingOrDowngrades() {
        #expect(GitHubPublishedInstaller.isNewer("1.12.0", than: "1.9.0") == true)
        #expect(GitHubPublishedInstaller.isNewer("1.12.0", than: "1.12.0") == false)
        #expect(GitHubPublishedInstaller.isNewer("1.11.0", than: "1.12.0") == false)
        #expect(GitHubPublishedInstaller.isNewer("1.12.0", than: "invalid") == nil)
    }

    @Test func rejectsHTTPFailuresBeforeParsingReleases() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailedReleaseURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        await #expect(throws: GitHubPublishedInstallerError.unavailable) {
            try await GitHubPublishedInstallerLookup.load(from: URL(string: "https://updates.test/releases")!, session: session)
        }
    }

    @Test @MainActor func repeatedManualClicksJoinOneInFlightCheck() async {
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        var startedEvents = started.makeAsyncIterator()
        var resume: CheckedContinuation<GitHubPublishedInstaller, Error>?
        var calls = 0
        var feedback: [UpdateEvent] = []
        let checker = GitHubUpdateChecker(
            currentVersion: "1.12.0", defaults: isolatedDefaults(), startAutomatically: false,
            loadInstaller: {
                calls += 1
                return try await withCheckedThrowingContinuation { continuation in
                    resume = continuation
                    startedContinuation.yield(())
                }
            },
            present: { event, _ in feedback.append(event) }
        )
        var events = checker.events.makeAsyncIterator()
        checker.checkForUpdates()
        #expect(await events.next() == .checking)
        _ = await startedEvents.next()
        checker.checkForUpdates()
        checker.checkForUpdates()
        #expect(calls == 1)
        resume?.resume(returning: installer(version: "1.13.0"))
        #expect(await events.next() == .available(version: "1.13.0"))
        #expect(feedback == [.available(version: "1.13.0")])
    }

    @Test @MainActor func manualChecksAlwaysReportCurrentAvailableAndNetworkFailure() async {
        for (releaseVersion, expected) in [
            ("1.11.0", UpdateEvent.current),
            ("1.12.0", UpdateEvent.current),
            ("1.13.0", UpdateEvent.available(version: "1.13.0"))
        ] {
            var feedback: [UpdateEvent] = []
            let checker = GitHubUpdateChecker(
                currentVersion: "1.12.0", defaults: isolatedDefaults(), startAutomatically: false,
                loadInstaller: { installer(version: releaseVersion) },
                present: { event, _ in feedback.append(event) }
            )
            var events = checker.events.makeAsyncIterator()
            checker.checkForUpdates()
            #expect(await events.next() == .checking)
            #expect(await events.next() == expected)
            #expect(feedback == [expected])
        }
        var feedback: [UpdateEvent] = []
        let checker = GitHubUpdateChecker(
            currentVersion: "1.12.0", defaults: isolatedDefaults(), startAutomatically: false,
            loadInstaller: { throw URLError(.notConnectedToInternet) },
            present: { event, _ in feedback.append(event) }
        )
        var events = checker.events.makeAsyncIterator()
        checker.checkForUpdates()
        #expect(await events.next() == .checking)
        #expect(await events.next() == .failed(.network))
        #expect(feedback == [.failed(.network)])
    }

    @Test @MainActor func automaticPreferencePersistsAndChecksRespectDailyFrequency() async {
        let defaults = isolatedDefaults()
        var calls = 0
        var feedback: [UpdateEvent] = []
        let checker = GitHubUpdateChecker(
            currentVersion: "1.12.0", defaults: defaults, startAutomatically: false,
            loadInstaller: { calls += 1; return installer(version: "1.13.0") },
            present: { event, _ in feedback.append(event) }
        )
        var events = checker.events.makeAsyncIterator()
        checker.automaticallyChecksForUpdates = false
        checker.checkAutomaticallyIfDue()
        #expect(calls == 0)
        #expect(defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool == false)
        checker.automaticallyChecksForUpdates = true
        checker.checkAutomaticallyIfDue()
        #expect(await events.next() == .checking)
        #expect(await events.next() == .available(version: "1.13.0"))
        checker.checkAutomaticallyIfDue()
        #expect(calls == 1)
        #expect(feedback.count == 1)
        defaults.set(Date(timeIntervalSinceNow: -90_000), forKey: GitHubUpdateChecker.lastCheckKey)
        checker.checkAutomaticallyIfDue()
        #expect(await events.next() == .checking)
        #expect(await events.next() == .available(version: "1.13.0"))
        #expect(calls == 2)
        #expect(feedback.count == 1)
        let relaunched = GitHubUpdateChecker(
            currentVersion: "1.12.0", defaults: defaults, startAutomatically: false,
            loadInstaller: { installer(version: "1.13.0") }, present: { _, _ in }
        )
        #expect(relaunched.automaticallyChecksForUpdates)
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "GitHubUpdateCheckerTests.\(UUID().uuidString)")!
    }

    private func installer(version: String) -> GitHubPublishedInstaller {
        GitHubPublishedInstaller(
            version: version, notes: "", downloadURL: GitHubPublishedInstaller.releasesURL,
            fileName: "Prism-\(version).dmg"
        )
    }
}

private final class FailedReleaseURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
