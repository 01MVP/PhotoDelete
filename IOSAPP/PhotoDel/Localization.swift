import Foundation

enum L10n {
    static func string(_ value: String.LocalizationValue) -> String {
        String(localized: value, table: "Localizable", bundle: AppLanguage.current.localizationBundle)
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
}

extension String {
    var appLocalized: String {
        L10n.key(self)
    }
}
