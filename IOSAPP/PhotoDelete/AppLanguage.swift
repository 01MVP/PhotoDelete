import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case ar
    case bn
    case ca
    case cs
    case da
    case de
    case el
    case en
    case es
    case esMX = "es-MX"
    case fi
    case fr
    case frCA = "fr-CA"
    case gu
    case he
    case hi
    case hr
    case hu
    case indonesian = "id"
    case it
    case ja
    case kn
    case ko
    case ms
    case ml
    case mr
    case nl
    case no
    case or
    case pa
    case pl
    case ptBR = "pt-BR"
    case ptPT = "pt-PT"
    case ro
    case ru
    case sk
    case sl
    case sv
    case ta
    case te
    case th
    case tr
    case uk
    case ur
    case vi
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"

    var id: String { rawValue }

    static let supportedStoreMetadataLocales = [
        "ar-SA", "bn-BD", "ca", "cs", "da", "de-DE", "el", "en-AU", "en-CA", "en-GB", "en-US",
        "es-ES", "es-MX", "fi", "fr-CA", "fr-FR", "gu-IN", "he", "hi", "hr", "hu", "id", "it",
        "ja", "kn-IN", "ko", "ml-IN", "mr-IN", "ms", "nl-NL", "no", "or-IN", "pa-IN", "pl",
        "pt-BR", "pt-PT", "ro", "ru", "sk", "sl-SI", "sv", "ta-IN", "te-IN", "th", "tr", "uk",
        "ur-PK", "vi", "zh-Hans", "zh-Hant"
    ]

    static var appLanguages: [AppLanguage] {
        [.ar, .de, .en, .ja, .zhHans, .zhHant]
    }

    static var current: AppLanguage {
        let storedValue = UserDefaults.standard.string(forKey: AppConstants.appLanguageKey) ?? AppLanguage.system.rawValue
        return AppLanguage(rawValue: storedValue) ?? .system
    }

    var localizationBundle: Bundle {
        guard self != .system else { return .main }

        let resourceCandidates = [rawValue, baseLanguageCode]
            .compactMap { $0 }
            .removingDuplicates()

        for resource in resourceCandidates {
            if let path = Bundle.main.path(forResource: resource, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }

        return .main
    }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        default:
            return Locale(identifier: rawValue)
        }
    }

    var title: String {
        switch self {
        case .system:
            return L10n.string("跟随系统")
        default:
            return nativeName
        }
    }

    var detail: String {
        switch self {
        case .system:
            return L10n.string("自动匹配 iPhone 的首选语言")
        default:
            return englishName
        }
    }

    var searchTokens: [String] {
        [
            rawValue,
            baseLanguageCode,
            nativeName,
            englishName,
            locale.localizedString(forIdentifier: rawValue),
            Locale.autoupdatingCurrent.localizedString(forIdentifier: rawValue)
        ]
        .compactMap { $0 }
        .removingDuplicates()
    }

    var isRightToLeft: Bool {
        switch self {
        case .ar, .he, .ur:
            return true
        default:
            return false
        }
    }

    var showsSimplifiedChineseOnlyContent: Bool {
        switch self {
        case .zhHans:
            return true
        case .system:
            guard let firstLanguage = Locale.preferredLanguages.first else { return false }
            return AppLanguage.isSimplifiedChineseLanguageIdentifier(firstLanguage)
        default:
            return false
        }
    }

    var usesChineseText: Bool {
        switch self {
        case .zhHans, .zhHant:
            return true
        case .system:
            guard let firstLanguage = Locale.preferredLanguages.first else { return false }
            return AppLanguage.isChineseLanguageIdentifier(firstLanguage)
        default:
            return false
        }
    }

    private var baseLanguageCode: String? {
        rawValue.split(separator: "-").first.map(String.init)
    }

    private var nativeName: String {
        switch self {
        case .system:
            return L10n.string("跟随系统")
        case .zhHans:
            return "简体中文"
        case .zhHant:
            return "繁體中文"
        case .esMX:
            return "español (México)"
        case .frCA:
            return "français (Canada)"
        case .ptBR:
            return "português (Brasil)"
        case .ptPT:
            return "português (Portugal)"
        default:
            return locale.localizedString(forIdentifier: rawValue) ?? englishName
        }
    }

    private var englishName: String {
        switch self {
        case .system:
            return "System"
        case .ar:
            return "Arabic"
        case .bn:
            return "Bangla"
        case .ca:
            return "Catalan"
        case .cs:
            return "Czech"
        case .da:
            return "Danish"
        case .de:
            return "German"
        case .el:
            return "Greek"
        case .en:
            return "English"
        case .es:
            return "Spanish"
        case .esMX:
            return "Spanish (Mexico)"
        case .fi:
            return "Finnish"
        case .fr:
            return "French"
        case .frCA:
            return "French (Canada)"
        case .gu:
            return "Gujarati"
        case .he:
            return "Hebrew"
        case .hi:
            return "Hindi"
        case .hr:
            return "Croatian"
        case .hu:
            return "Hungarian"
        case .indonesian:
            return "Indonesian"
        case .it:
            return "Italian"
        case .ja:
            return "Japanese"
        case .kn:
            return "Kannada"
        case .ko:
            return "Korean"
        case .ms:
            return "Malay"
        case .ml:
            return "Malayalam"
        case .mr:
            return "Marathi"
        case .nl:
            return "Dutch"
        case .no:
            return "Norwegian"
        case .or:
            return "Odia"
        case .pa:
            return "Punjabi"
        case .pl:
            return "Polish"
        case .ptBR:
            return "Portuguese (Brazil)"
        case .ptPT:
            return "Portuguese (Portugal)"
        case .ro:
            return "Romanian"
        case .ru:
            return "Russian"
        case .sk:
            return "Slovak"
        case .sl:
            return "Slovenian"
        case .sv:
            return "Swedish"
        case .ta:
            return "Tamil"
        case .te:
            return "Telugu"
        case .th:
            return "Thai"
        case .tr:
            return "Turkish"
        case .uk:
            return "Ukrainian"
        case .ur:
            return "Urdu"
        case .vi:
            return "Vietnamese"
        case .zhHans:
            return "Simplified Chinese"
        case .zhHant:
            return "Traditional Chinese"
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

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
