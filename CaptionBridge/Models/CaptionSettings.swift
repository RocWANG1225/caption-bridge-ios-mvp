import SwiftUI
import UIKit

enum CaptionTheme: String, CaseIterable, Identifiable {
    case system
    case blackWhite
    case whiteBlack
    case yellowBlack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .blackWhite: "黑底白字"
        case .whiteBlack: "白底黑字"
        case .yellowBlack: "黄字黑底"
        }
    }
}

@MainActor
final class CaptionSettings: ObservableObject {
    @Published var fontScale: Double {
        didSet { UserDefaults.standard.set(fontScale, forKey: "captionFontScale") }
    }

    @Published var landscapeMode: Bool {
        didSet { UserDefaults.standard.set(landscapeMode, forKey: "familyLandscapeMode") }
    }

    @Published var privacyAutoClear: Bool {
        didSet { UserDefaults.standard.set(privacyAutoClear, forKey: "privacyAutoClear") }
    }

    private var storedTheme: String {
        didSet { UserDefaults.standard.set(storedTheme, forKey: "captionTheme") }
    }

    init() {
        let defaults = UserDefaults.standard
        fontScale = defaults.object(forKey: "captionFontScale") as? Double ?? 1.0
        landscapeMode = defaults.object(forKey: "familyLandscapeMode") as? Bool ?? false
        privacyAutoClear = defaults.object(forKey: "privacyAutoClear") as? Bool ?? true
        storedTheme = defaults.string(forKey: "captionTheme") ?? CaptionTheme.blackWhite.rawValue
    }

    var theme: CaptionTheme {
        get { CaptionTheme(rawValue: storedTheme) ?? .blackWhite }
        set {
            storedTheme = newValue.rawValue
            objectWillChange.send()
        }
    }

    var background: Color {
        switch theme {
        case .system: Color(uiColor: .systemBackground)
        case .blackWhite, .yellowBlack: .black
        case .whiteBlack: .white
        }
    }

    var primaryText: Color {
        switch theme {
        case .system: Color(uiColor: .label)
        case .blackWhite: .white
        case .whiteBlack: .black
        case .yellowBlack: .yellow
        }
    }

    var secondaryText: Color {
        switch theme {
        case .system: Color(uiColor: .secondaryLabel)
        case .blackWhite: Color.white.opacity(0.72)
        case .whiteBlack: Color.black.opacity(0.62)
        case .yellowBlack: Color.yellow.opacity(0.72)
        }
    }
}
