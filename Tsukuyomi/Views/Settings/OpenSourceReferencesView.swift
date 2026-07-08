import SwiftUI

struct OpenSourceReferencesView: View {
    private let references: [OpenSourceReference] = [
        .init(
            name: "SakuraRSS",
            repositoryURL: "https://github.com/katagaki/SakuraRSS",
            usage: String(
                localized: "settings.opensource.sakura.usage",
                defaultValue: "Tsukuyomi borrows article extraction cleanup ideas, YouTube feed discovery patterns, and dedicated YouTube player flow refinements from SakuraRSS where they directly improved this app."
            )
        ),
        .init(
            name: "SwiftSoup",
            repositoryURL: "https://github.com/scinfu/SwiftSoup",
            usage: String(
                localized: "settings.opensource.swiftsoup.usage",
                defaultValue: "Tsukuyomi uses SwiftSoup for HTML parsing and article content cleanup."
            )
        )
    ]

    var body: some View {
        List {
            Section(String(localized: "settings.opensource.section.used", defaultValue: "Used in Tsukuyomi")) {
                ForEach(references) { reference in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(reference.name)
                            .font(.headline)
                        Text(reference.usage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = URL(string: reference.repositoryURL) {
                            Link(reference.repositoryURL, destination: url)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.accentCinder)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }
            }

            Section(String(localized: "settings.opensource.section.note", defaultValue: "Note")) {
                Text(
                    String(
                        localized: "settings.opensource.note.body",
                        defaultValue: "Only repositories that are currently referenced in Tsukuyomi's code or implementation flow are listed here."
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
            }
        }
        .tsukuyomiListSurface()
        .navigationTitle(String(localized: "settings.openSource.title", defaultValue: "Open Source"))
    }
}

private struct OpenSourceReference: Identifiable {
    let id = UUID()
    let name: String
    let repositoryURL: String
    let usage: String
}
