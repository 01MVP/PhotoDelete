import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en

    var id: String { rawValue }

    static var current: AppLanguage {
        let storedValue = UserDefaults.standard.string(forKey: AppConstants.appLanguageKey) ?? AppLanguage.system.rawValue
        return AppLanguage(rawValue: storedValue) ?? .system
    }

    var localizationBundle: Bundle {
        switch self {
        case .system:
            return .main
        case .zhHans, .zhHant, .en:
            guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
                  let bundle = Bundle(path: path) else {
                return .main
            }
            return bundle
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .zhHans:
            return Locale(identifier: "zh-Hans")
        case .zhHant:
            return Locale(identifier: "zh-Hant")
        case .en:
            return Locale(identifier: "en")
        }
    }

    var title: String {
        switch self {
        case .system:
            return L10n.string("跟随系统")
        case .zhHans:
            return L10n.string("简体中文")
        case .zhHant:
            return L10n.string("繁體中文")
        case .en:
            return L10n.string("English")
        }
    }

    var detail: String {
        switch self {
        case .system:
            return L10n.string("自动匹配 iPhone 的首选语言")
        case .zhHans:
            return L10n.string("始终使用简体中文")
        case .zhHant:
            return L10n.string("始終使用繁體中文")
        case .en:
            return L10n.string("Always use English")
        }
    }

    var showsSimplifiedChineseOnlyContent: Bool {
        switch self {
        case .zhHans:
            return true
        case .zhHant, .en:
            return false
        case .system:
            guard let firstLanguage = Locale.preferredLanguages.first else { return false }
            return AppLanguage.isSimplifiedChineseLanguageIdentifier(firstLanguage)
        }
    }

    var usesChineseText: Bool {
        switch self {
        case .zhHans, .zhHant:
            return true
        case .en:
            return false
        case .system:
            guard let firstLanguage = Locale.preferredLanguages.first else { return false }
            return AppLanguage.isChineseLanguageIdentifier(firstLanguage)
        }
    }

    private static func isSimplifiedChineseLanguageIdentifier(_ identifier: String) -> Bool {
        let normalized = identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if normalized.hasPrefix("zh-hant") ||
            normalized.hasPrefix("zh-tw") ||
            normalized.hasPrefix("zh-hk") ||
            normalized.hasPrefix("zh-mo") {
            return false
        }

        return normalized == "zh" ||
            normalized.hasPrefix("zh-hans") ||
            normalized.hasPrefix("zh-cn") ||
            normalized.hasPrefix("zh-sg") ||
            normalized.hasPrefix("zh-my")
    }

    private static func isChineseLanguageIdentifier(_ identifier: String) -> Bool {
        identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
            .hasPrefix("zh")
    }
}
