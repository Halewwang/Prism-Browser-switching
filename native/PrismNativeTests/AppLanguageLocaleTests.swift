import PrismCore
import Testing
@testable import PrismNative

@Suite("App language")
struct AppLanguageTests {
    @Test func explicitLanguagesUseStableBundleCodes() {
        #expect(AppLanguage.system.interfaceLocalizationCode == nil)
        #expect(AppLanguage.english.interfaceLocalizationCode == "en")
        #expect(AppLanguage.simplifiedChinese.interfaceLocalizationCode == "zh-Hans")
    }
}
