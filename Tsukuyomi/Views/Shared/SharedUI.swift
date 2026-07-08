import SwiftUI
import UIKit

enum TsukuyomiLayout {
    static let horizontalPadding: CGFloat = 20
    static let readableMaxWidth: CGFloat = 720
    static let rowSpacing: CGFloat = 14
    static let thumbnailSize: CGFloat = 92
}

struct ArticleRow: View {
    @Environment(SettingsStore.self) private var settingsStore
    let article: FeedArticle

    var body: some View {
        HStack(alignment: .top, spacing: TsukuyomiLayout.rowSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(article.feedTitle.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentCinder)
                        .lineLimit(1)
                    if !article.isRead {
                        Circle()
                            .fill(Color.accentCinder)
                            .frame(width: 8, height: 8)
                    }
                }

                switch settingsStore.titleTranslationDisplayMode {
                case .original:
                    titleText(article.title)
                case .translationOnly:
                    titleText(article.aiTitleTranslation?.nilIfBlank ?? article.title)
                case .bilingual:
                    VStack(alignment: .leading, spacing: 6) {
                        titleText(article.title)
                        if let translation = article.aiTitleTranslation?.nilIfBlank {
                            titleText(translation)
                        }
                    }
                }

                if let publishedDate = article.publishedDate {
                    Text(publishedDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: TsukuyomiLayout.thumbnailSize, alignment: .topLeading)

            thumbnailView
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func titleText(_ title: String) -> some View {
        WordWrappingText(
            title,
            font: settingsStore.titleFont.uiFont(textStyle: .headline, weight: .bold)
        )
        .foregroundStyle(Color.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        Group {
            if let imageURL = article.imageURL,
               let url = URL(string: imageURL) {
                CachedRemoteImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.clear
                }
            } else {
                Color.clear
            }
        }
        .frame(width: TsukuyomiLayout.thumbnailSize, height: TsukuyomiLayout.thumbnailSize)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct EmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
    }
}

struct TsukuyomiActionButton: View {
    let title: String
    let systemImage: String
    var isActive = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isActive ? Color.accentCinder : Color.buttonSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(isActive ? Color.white : Color.accentCinder)
            .contentShape(Rectangle())
    }
}

struct TsukuyomiForceableActionButton: View {
    let title: String
    let systemImage: String
    var isActive = false
    let action: () -> Void
    let forceAction: () -> Void

    @State private var suppressNextTap = false

    var body: some View {
        Button {
            guard !suppressNextTap else {
                suppressNextTap = false
                return
            }
            action()
        } label: {
            TsukuyomiActionButton(title: title, systemImage: systemImage, isActive: isActive)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                suppressNextTap = true
                forceAction()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    suppressNextTap = false
                }
            }
        )
    }
}

struct BrowserSheetDestination: Identifiable {
    let id = UUID()
    let url: URL
}

struct TsukuyomiBackdrop: View {
    var body: some View {
        Color.pageBackgroundTop
            .ignoresSafeArea()
    }
}

struct WordWrappingText: UIViewRepresentable {
    let text: String
    let font: UIFont
    var color: UIColor = .label

    init(_ text: String, font: UIFont, color: UIColor = .label) {
        self.text = text
        self.font = font
        self.color = color
    }

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.lineBreakStrategy = []
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else {
            return nil
        }
        let fittingSize = uiView.sizeThatFits(
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: ceil(fittingSize.height))
    }
}

struct TsukuyomiListSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(TsukuyomiBackdrop())
            .listStyle(.insetGrouped)
    }
}

extension View {
    func tsukuyomiListSurface() -> some View {
        modifier(TsukuyomiListSurface())
    }
}

extension Color {
    static let accentCinder = Color(light: "#EC6649", dark: "#FE5A3D")
    static let buttonSurface = Color(light: "#EADCD3", dark: "#291915")
    static let pageBackgroundTop = Color(light: "#ECEAE3", dark: "#1B1B1B")
    static let pageBackgroundMid = Color(light: "#ECEAE3", dark: "#1B1B1B")
    static let pageBackgroundBottom = Color(light: "#ECEAE3", dark: "#1B1B1B")
    static let primaryText = Color(light: "#2E2A24", dark: "#F4EEE7")
    static let cardSurface = Color(light: "#ECEAE3", dark: "#1B1B1B")
    static let placeholderText = Color(uiColor: .placeholderText)

    init(light: String, dark: String) {
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
