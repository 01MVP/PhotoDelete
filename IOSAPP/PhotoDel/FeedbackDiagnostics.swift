import Foundation

#if canImport(UIKit)
import UIKit
#endif

enum FeedbackDiagnostics {
    static func emailBody() -> String {
        [
            L10n.string("请在此处写下您的反馈和建议："),
            "",
            "",
            "",
            "---",
            "App: PhotoDel v\(AppConstants.displayVersion)",
            "Device: \(deviceDisplayName)",
            "iOS: \(systemDisplayName)",
            "Anonymous User ID: \(anonymousUserID)"
        ].joined(separator: "\n")
    }

    static var anonymousUserID: String {
        let defaults = UserDefaults.standard
        if let existingID = defaults.string(forKey: AppConstants.anonymousUserIDKey), !existingID.isEmpty {
            return existingID
        }

        let newID = "$PhotoDelAnonymousID:\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        defaults.set(newID, forKey: AppConstants.anonymousUserIDKey)
        return newID
    }

    private static var deviceDisplayName: String {
        #if canImport(UIKit)
        return "\(UIDevice.current.model) (\(machineIdentifier))"
        #else
        return "Unknown"
        #endif
    }

    private static var systemDisplayName: String {
        #if canImport(UIKit)
        return "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    private static var machineIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)

        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier.append(String(UnicodeScalar(UInt8(value))))
        }
    }
}
