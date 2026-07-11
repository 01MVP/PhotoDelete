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

enum AppDateFormatter {
    private static func cachedFormatter(
        key: String,
        configure: (DateFormatter) -> Void
    ) -> DateFormatter {
        let cacheKey = "PhotoDelete.DateFormatter.\(key)" as NSString
        if let formatter = Thread.current.threadDictionary[cacheKey] as? DateFormatter {
            return formatter
        }

        let formatter = DateFormatter()
        configure(formatter)
        Thread.current.threadDictionary[cacheKey] = formatter
        return formatter
    }

    static func string(
        from date: Date,
        template: String,
        locale: Locale = AppLanguage.current.locale
    ) -> String {
        configuredFormatter(template: template, locale: locale).string(from: date)
    }

    static func string(
        from date: Date,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style
    ) -> String {
        let locale = AppLanguage.current.locale
        let formatter = cachedFormatter(
            key: "style|\(locale.identifier)|\(dateStyle.rawValue)|\(timeStyle.rawValue)"
        ) { formatter in
            formatter.locale = locale
            formatter.dateStyle = dateStyle
            formatter.timeStyle = timeStyle
        }
        return formatter.string(from: date)
    }

    static func configuredFormatter(
        template: String,
        locale: Locale = AppLanguage.current.locale
    ) -> DateFormatter {
        cachedFormatter(key: "template|\(locale.identifier)|\(template)") { formatter in
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate(template)
        }
    }
}

extension String {
    var appLocalized: String {
        L10n.key(self)
    }
}
