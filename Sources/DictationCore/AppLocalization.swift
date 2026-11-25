import Foundation

public enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", russian = "ru"
    public var id: String { rawValue }

    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        switch self {
        case .english: return .english
        case .russian: return .russian
        case .system:
            let primary = preferredLanguages.first ?? "en"
            return Locale(identifier: primary).language.languageCode?.identifier == "ru" ? .russian : .english
        }
    }
}

public enum AppLanguage: String { case english = "en", russian = "ru" }

/// Explicit bundles allow changing the app language immediately, independently
/// of the speech language and without modifying Apple's global preferences.
public struct AppLocalization {
    public let language: AppLanguage
    private let bundle: Bundle

    public init(language: AppLanguage) {
        self.language = language
        let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj")!
        bundle = Bundle(path: path)!
    }

    public func text(_ key: String, _ arguments: String...) -> String {
        resolve(key, arguments: arguments)
    }

    public func resolve(_ key: String, arguments: [String] = []) -> String {
        let template = bundle.localizedString(forKey: key, value: nil, table: nil)
        guard !arguments.isEmpty else { return template }
        return String(format: template, locale: Locale(identifier: language.rawValue), arguments: arguments)
    }
}

/// Store the message, not its translation, so status/error panels also update
/// when the user changes language. External diagnostic details remain verbatim.
public enum AppMessage {
    case key(String)
    case format(String, [String])
    case literal(String)

    public func resolve(using localization: AppLocalization) -> String {
        switch self {
        case .key(let key): return localization.text(key)
        case .format(let key, let arguments): return localization.resolve(key, arguments: arguments)
        case .literal(let value): return value
        }
    }
}
