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

@Test func sanitizerRemovesQueryDelimiterWhenEveryItemIsSensitive() {
    let input = URL(string: "custom://user:pass@example.com:8080/doc?code=one&STATE=two&fbclid=three#section")!

    let sanitized = URLSanitizer.default.sanitize(input)

    #expect(sanitized?.absoluteString == "custom://user:pass@example.com:8080/doc")
}

@Test func sanitizerRemovesFragmentWhenThereIsNoQuery() {
    let input = URL(string: "https://example.com/doc#section")!

    let sanitized = URLSanitizer.default.sanitize(input)

    #expect(sanitized?.absoluteString == "https://example.com/doc")
}
