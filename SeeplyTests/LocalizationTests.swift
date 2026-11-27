import Foundation
import XCTest
#if canImport(SeeplyCore)
@testable import SeeplyCore
#else
@testable import Seeply
#endif

final class LocalizationTests: XCTestCase {
    func testTraditionalScriptsUseTraditionalChinese() {
        for tag in ["zh-Hant", "zh-Hant-TW", "zh-Hant-HK", "ZH_hAnT_MO", "cmn-Hant-TW", "yue-Hant-HK"] {
            XCTAssertEqual(InterfaceLanguage.systemDefault(preferredLanguages: [tag]), .traditionalChinese, tag)
        }
    }

    func testTraditionalRegionsWithoutAScriptAreRecognized() {
        for tag in ["zh-TW", "zh_HK", "zh-MO"] {
            XCTAssertEqual(InterfaceLanguage.systemDefault(preferredLanguages: [tag]), .traditionalChinese, tag)
        }
    }

    func testOtherPrimaryLanguagesDefaultToEnglish() {
        for tag in ["en", "en-US", "ja-JP", "fr-FR", "de", "zh-Hans", "zh-CN", "zh-SG", "zh"] {
            XCTAssertEqual(InterfaceLanguage.systemDefault(preferredLanguages: [tag]), .english, tag)
        }
    }

    func testAnExplicitScriptTakesPriorityOverTheRegion() {
        XCTAssertEqual(InterfaceLanguage.systemDefault(preferredLanguages: ["zh-Hans-TW"]), .english)
        XCTAssertEqual(InterfaceLanguage.systemDefault(preferredLanguages: ["zh-Latn-TW"]), .english)
        XCTAssertEqual(InterfaceLanguage.systemDefault(preferredLanguages: ["zh-Hant-CN"]), .traditionalChinese)
    }

    func testSecondaryChineseNeverOverridesAnotherPrimaryLanguage() {
        XCTAssertEqual(InterfaceLanguage.systemDefault(preferredLanguages: ["ja-JP", "zh-Hant", "en"]), .english)
        XCTAssertEqual(InterfaceLanguage.systemDefault(preferredLanguages: ["en", "zh-TW"]), .english)
        XCTAssertEqual(InterfaceLanguage.systemDefault(preferredLanguages: ["fr", "zh-Hant-HK"]), .english)
    }

    func testManualLanguageChoicesOverrideTheSystem() {
        XCTAssertEqual(LanguagePreference.english.resolved(preferredLanguages: ["zh-Hant"]), .english)
        XCTAssertEqual(LanguagePreference.traditionalChinese.resolved(preferredLanguages: ["de"]), .traditionalChinese)
        XCTAssertEqual(LanguagePreference.system.resolved(preferredLanguages: ["zh-Hant-TW"]), .traditionalChinese)
    }

    func testMissingOrUnknownPrimaryLanguageUsesEnglish() {
        for preferences in [[], [""], ["und"], ["", "zh-Hant"]] as [[String]] {
            XCTAssertEqual(InterfaceLanguage.systemDefault(preferredLanguages: preferences), .english)
        }
    }

    func testEveryCatalogEntryHasEnglishAndTraditionalChineseText() {
        XCTAssertGreaterThan(StringCatalog.traditionalChinese.count, 100)
        for (english, chinese) in StringCatalog.traditionalChinese {
            XCTAssertFalse(english.isEmpty)
            XCTAssertFalse(chinese.isEmpty)
            XCTAssertEqual(StringCatalog.text(english, language: .english), english)
            XCTAssertEqual(StringCatalog.text(english, language: .traditionalChinese), chinese)
        }
    }

    func testTranslationsKeepAllTemplateArguments() throws {
        let regex = try NSRegularExpression(pattern: #"\{([A-Za-z_]+)\}"#)
        func arguments(_ text: String) -> Set<String> {
            Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range(at: 1), in: text).map { String(text[$0]) }
            })
        }
        for (english, chinese) in StringCatalog.traditionalChinese {
            XCTAssertEqual(arguments(english), arguments(chinese), english)
        }
    }

    func testBracesInArgumentsAreNotInterpretedAsMoreTemplates() {
        let values = ["label": "{value}", "value": "photo {label}.jpg"]
        XCTAssertEqual(StringCatalog.text("{label}: {value}", language: .english, arguments: values), "{value}: photo {label}.jpg")
        XCTAssertEqual(StringCatalog.text("{label}: {value}", language: .traditionalChinese, arguments: values), "{value}：photo {label}.jpg")
    }

    func testRawMetadataValuesAreNeverTranslated() {
        XCTAssertEqual(DisplayText.literal("Auto").resolved(in: .traditionalChinese), "Auto")
        XCTAssertEqual(DisplayText.key("Auto").resolved(in: .traditionalChinese), "自動")
        XCTAssertEqual(DisplayText.literal("相片 {name}.jpg").resolved(in: .english), "相片 {name}.jpg")
    }

    func testCachedMetadataCanBeCopiedInBothLanguagesWithoutRebuildingIt() {
        let metadata = ImageMetadata(fileName: "Auto.jpg", camera: "Auto", lens: nil, aperture: nil,
            exposure: nil, iso: nil, focalLength: nil, sections: [
                MetadataSection(title: .key("Equipment"), entries: [
                    MetadataEntry(label: .key("Camera"), value: .literal("Auto")),
                    MetadataEntry(label: .key("White bal."), value: .key("Auto"))
                ])
            ], rawSections: [])
        XCTAssertTrue(metadata.copyText(language: .english).contains("Camera: Auto"))
        XCTAssertTrue(metadata.copyText(language: .traditionalChinese).contains("相機：Auto"))
        XCTAssertTrue(metadata.copyText(language: .traditionalChinese).contains("白平衡：自動"))
        XCTAssertEqual(metadata.sections[0].entries[0].id, "Camera")
    }

    func testStructuredErrorsTranslateAtDisplayTime() {
        enum SampleError: PresentableError {
            case empty
            var displayText: DisplayText { .key("This folder contains no images that can be displayed.") }
        }
        let message = DisplayText.error(SampleError.empty)
        XCTAssertEqual(message.resolved(in: .english), "This folder contains no images that can be displayed.")
        XCTAssertEqual(message.resolved(in: .traditionalChinese), "這個資料夾內沒有可顯示的圖片。")
    }

    func testCachedFileSizesUseLanguageIndependentSIUnits() {
        XCTAssertEqual(MetadataFormatter.fileSize(0), "0 B")
        XCTAssertEqual(MetadataFormatter.fileSize(1500), "1.5 KB")
        XCTAssertEqual(MetadataFormatter.fileSize(25_000_000), "25 MB")
        XCTAssertEqual(MetadataFormatter.fileSize(-1), "0 B")
    }
}
