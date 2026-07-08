import SwiftUI
import UIKit

enum ReadingFontChoice: String, CaseIterable, Codable, Identifiable {
    case system
    case newYork
    case avenirNext
    case charter
    case georgia
    case palatino
    case timesNewRoman
    case helveticaNeue
    case menlo
    case hiraginoMincho
    case hiraginoSans

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return String(localized: "font.system", defaultValue: "System")
        case .newYork:
            return "New York"
        case .avenirNext:
            return "Avenir Next"
        case .charter:
            return "Charter"
        case .georgia:
            return "Georgia"
        case .palatino:
            return "Palatino"
        case .timesNewRoman:
            return "Times New Roman"
        case .helveticaNeue:
            return "Helvetica Neue"
        case .menlo:
            return "Menlo"
        case .hiraginoMincho:
            return "Hiragino Mincho"
        case .hiraginoSans:
            return "Hiragino Sans"
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system:
            return .system(size: size, weight: weight)
        case .newYork:
            return .system(size: size, weight: weight, design: .serif)
        default:
            return .custom(preferredPostScriptName(weight: weight), size: size)
        }
    }

    func uiFont(textStyle: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle)
        let pointSize = descriptor.pointSize
        switch self {
        case .system:
            return .systemFont(ofSize: pointSize, weight: weight)
        case .newYork:
            return UIFont(descriptor: descriptor.withDesign(.serif) ?? descriptor, size: pointSize).weighted(weight)
        default:
            let name = preferredPostScriptName(weight: Font.Weight(weight))
            return UIFont(name: name, size: pointSize)?.weighted(weight) ?? .systemFont(ofSize: pointSize, weight: weight)
        }
    }

    private func preferredPostScriptName(weight: Font.Weight) -> String {
        let bold = weight.isBoldLike
        switch self {
        case .system:
            return ".SFUI-Regular"
        case .newYork:
            return ".NewYork-Regular"
        case .avenirNext:
            return bold ? "AvenirNext-Bold" : "AvenirNext-Regular"
        case .charter:
            return bold ? "Charter-Bold" : "Charter-Roman"
        case .georgia:
            return bold ? "Georgia-Bold" : "Georgia"
        case .palatino:
            return bold ? "Palatino-Bold" : "Palatino-Roman"
        case .timesNewRoman:
            return bold ? "TimesNewRomanPS-BoldMT" : "TimesNewRomanPSMT"
        case .helveticaNeue:
            return bold ? "HelveticaNeue-Bold" : "HelveticaNeue"
        case .menlo:
            return bold ? "Menlo-Bold" : "Menlo-Regular"
        case .hiraginoMincho:
            return bold ? "HiraMinProN-W6" : "HiraMinProN-W3"
        case .hiraginoSans:
            return bold ? "HiraginoSans-W6" : "HiraginoSans-W3"
        }
    }
}

private extension Font.Weight {
    init(_ uiWeight: UIFont.Weight) {
        switch uiWeight {
        case .black, .heavy, .bold, .semibold:
            self = .bold
        case .medium:
            self = .medium
        case .light, .thin, .ultraLight:
            self = .light
        default:
            self = .regular
        }
    }

    var isBoldLike: Bool {
        self == .bold || self == .semibold || self == .heavy || self == .black
    }
}

private extension UIFont {
    func weighted(_ weight: UIFont.Weight) -> UIFont {
        let traits: UIFontDescriptor.SymbolicTraits = weight >= .semibold ? .traitBold : []
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
