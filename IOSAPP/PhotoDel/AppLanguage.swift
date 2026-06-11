import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
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
        case .zhHans, .en:
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
        case .en:
            return L10n.string("Always use English")
        }
    }
}
