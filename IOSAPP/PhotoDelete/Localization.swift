import Foundation

enum L10n {
    static func string(_ value: String.LocalizationValue) -> String {
        String(localized: value, table: "Localizable", bundle: AppLanguage.current.localizationBundle)
    }

    static func attributedMarkdown(_ value: String.LocalizationValue) -> AttributedString {
        let markdown = string(value)
        return (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }

    static func key(_ key: String) -> String {
        AppLanguage.current.localizationBundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func percent(_ value: Int) -> String {
        string("\(value)%")
    }

    static func photoCount(_ count: Int) -> String {
        string("\(count) 张照片")
    }

    static func shortPhotoCount(_ count: Int) -> String {
        string("\(count) 张")
    }

    static var favoritesCategoryTitle: String {
        AppLanguage.current.usesChineseText ? string("收藏") : "Favorites"
    }
}

extension String {
    var appLocalized: String {
        L10n.key(self)
    }
}
