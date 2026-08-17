import Foundation
import Testing
@testable import PrismCore

@Test func sanitizerRemovesFragmentAndSensitiveParameters() {
    let input = URL(string: "https://example.com/doc?id=42&token=secret&utm_source=mail#section")!

    let sanitized = URLSanitizer.default.sanitize(input)

    #expect(sanitized?.absoluteString == "https://example.com/doc?id=42")
}

@Test func sanitizerRemovesCaseInsensitiveExactPrefixAndDuplicateSensitiveNames() {
    let input = URL(string: "https://example.com/doc?safe=one&Token=first&token=second&%75tm_campaign=spring&mytoken=allowed&note=token&AUTHORIZATION=third&utm_%73ource=mail&safe=two#section")!

    let sanitized = URLSanitizer.default.sanitize(input)

    #expect(sanitized?.absoluteString == "https://example.com/doc?safe=one&mytoken=allowed&note=token&safe=two")
}

@Test func sanitizerRemovesExpandedCredentialAndAPISecretParameterNames() {
    let input = URL(string: "https://example.com/doc?safe=one&PASSWORD=redacted&%73ecret=redacted&api_key=redacted&client_secret=redacted&refresh_token=redacted&safe=two#fragment")!

    let sanitized = URLSanitizer.default.sanitize(input)

    #expect(sanitized?.absoluteString == "https://example.com/doc?safe=one&safe=two")
}

@Test func sanitizerRemovesQueryDelimiterWhenEveryItemIsSensitive() {
    let input = URL(string: "custom://user:pass@example.com:8080/doc?code=one&STATE=two&fbclid=three#section")!

    let sanitized = URLSanitizer.default.sanitize(input)

    #expect(sanitized?.absoluteString == "custom://user:pass@example.com:8080/doc")
}

@Test func sanitizerRemovesHTTPUserInfoBeforeHistoryCanPersistOrReplayIt() {
    let input = URL(string: "https://private-user:private-password@example.com/doc?safe=kept#section")!

    let sanitized = URLSanitizer.default.sanitize(input)

    #expect(sanitized?.absoluteString == "https://example.com/doc?safe=kept")
    #expect(sanitized?.user == nil)
    #expect(sanitized?.password == nil)
}

@Test func sanitizerRemovesFragmentWhenThereIsNoQuery() {
    let input = URL(string: "https://example.com/doc#section")!

    let sanitized = URLSanitizer.default.sanitize(input)

    #expect(sanitized?.absoluteString == "https://example.com/doc")
}

@Test func sanitizerPreservesTheOriginalEncodingOfSafeQuerySegments() {
    let input = URL(string: "https://example.com/doc?safe=%2B%20%25&token=redacted")!

    let sanitized = URLSanitizer.default.sanitize(input)

    #expect(sanitized?.absoluteString == "https://example.com/doc?safe=%2B%20%25")
}

@Test(arguments: [
    "https://example.com/doc?token=redacted&",
    "https://example.com/doc?&token=redacted",
    "https://example.com/doc?token=redacted&&state=redacted"
])
func sanitizerRemovesDelimiterOnlySegmentsWhenNoSafeSegmentsRemain(_ input: String) {
    let sanitized = URLSanitizer.default.sanitize(URL(string: input)!)

    #expect(sanitized?.absoluteString == "https://example.com/doc")
}

@Test func sanitizerRetainsARealEmptyNameItem() {
    let input = URL(string: "https://example.com/doc?=value&token=redacted")!

    let sanitized = URLSanitizer.default.sanitize(input)

    #expect(sanitized?.absoluteString == "https://example.com/doc?=value")
}

@Test(arguments: [
    "token",
    "access_token",
    "auth",
    "authorization",
    "code",
    "state",
    "session",
    "session_id",
    "signature",
    "gclid",
    "fbclid",
    "password",
    "secret",
    "api_key",
    "client_secret",
    "refresh_token"
])
func sanitizerRemovesEveryCaseInsensitiveExactSensitiveName(_ name: String) {
    let input = URL(string: "https://example.com/doc?safe=keep&\(name.uppercased())=redacted&safe=again")!

    let sanitized = URLSanitizer.default.sanitize(input)

    #expect(sanitized?.absoluteString == "https://example.com/doc?safe=keep&safe=again")
}

@Test func sanitizerRemovesPercentEncodedSensitiveNamesAndUTMNames() {
    let input = URL(string: "https://example.com/doc?%74oken=redacted&%75tm_campaign=mail&safe=keep")!

    let sanitized = URLSanitizer.default.sanitize(input)

    #expect(sanitized?.absoluteString == "https://example.com/doc?safe=keep")
}

@Test func sanitizerRetainsSensitiveTextInsideSafeNamesAndValuesWithoutReencoding() {
    let input = URL(string: "custom://example/doc?mytoken=kept%2B&note=token%20value&safe=authorization%25&token=redacted#fragment")!

    let sanitized = URLSanitizer.default.sanitize(input)

    #expect(sanitized?.absoluteString == "custom://example/doc?mytoken=kept%2B&note=token%20value&safe=authorization%25")
}

@Test func sanitizerFailsClosedWhenAParameterNameCannotBeDecoded() {
    let input = URL(string: "https://example.com/doc?%FF=unknown&safe=keep")!

    let sanitized = URLSanitizer.default.sanitize(input)

    #expect(sanitized == nil)
}

@Test func sanitizerPreservesSafeDuplicatesOrderAndEncodedDelimiters() {
    let input = URL(string: "https://example.com/doc?safe=keep&safe=keep&token=redacted&safe=one%26token%3Dvalue&&")!

    let sanitized = URLSanitizer.default.sanitize(input)

    #expect(sanitized?.absoluteString == "https://example.com/doc?safe=keep&safe=keep&safe=one%26token%3Dvalue")
}
