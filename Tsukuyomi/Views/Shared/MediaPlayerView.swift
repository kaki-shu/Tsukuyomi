import SwiftUI
import AVFoundation
import AVKit
import WebKit

struct ArticleMediaSection: View {
    @Environment(AudioPlayerStore.self) private var audioPlayerStore
    let article: FeedArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let youtubePlayerURL {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "article.video.title", defaultValue: "Video"))
                        .font(.headline)
                    YouTubeEmbeddedPlayer(playerURL: youtubePlayerURL)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            } else if let videoURL = article.videoURL,
                      let url = URL(string: videoURL) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "article.video.title", defaultValue: "Video"))
                        .font(.headline)
                    NativeVideoPlayerCard(url: url)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }

            if let audioURL = article.audioURL,
               let url = URL(string: audioURL) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "article.audio.title", defaultValue: "Podcast"))
                        .font(.headline)
                    NativeAudioPlayerCard(
                        article: article,
                        url: url,
                        duration: article.mediaDuration
                    )
                }
            }
        }
    }

    private var youtubePlayerURL: URL? {
        for candidate in [article.videoURL, article.url] {
            guard let candidate,
                  let sourceURL = URL(string: candidate),
                  let host = sourceURL.host(percentEncoded: false)?.lowercased() else {
                continue
            }
            let identifier: String?
            if host.contains("youtu.be") {
                identifier = sourceURL.pathComponents.dropFirst().first
            } else if host.contains("youtube.com") {
                let components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)
                if sourceURL.path.contains("/watch") {
                    identifier = components?.queryItems?.first(where: { $0.name == "v" })?.value
                } else if sourceURL.path.contains("/embed/") {
                    identifier = sourceURL.pathComponents.last
                } else if sourceURL.path.contains("/shorts/") {
                    identifier = sourceURL.pathComponents.last
                } else {
                    identifier = nil
                }
            } else {
                identifier = nil
            }
            if let id = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
               !id.isEmpty {
                return URL(string: "https://www.youtube.com/embed/\(id)")
            }
        }
        return nil
    }
}

private struct NativeAudioPlayerCard: View {
    @Environment(AudioPlayerStore.self) private var audioPlayerStore
    let article: FeedArticle
    let url: URL
    let duration: Int?

    var body: some View {
        HStack(spacing: 14) {
            Button {
                if isCurrentPlaybackItem {
                    audioPlayerStore.togglePlayback()
                } else {
                    audioPlayerStore.play(
                        url: url,
                        title: article.title,
                        subtitle: article.feedTitle,
                        artworkURL: article.imageURL.flatMap(URL.init(string:))
                    )
                }
            } label: {
                Image(systemName: isCurrentPlaybackItem && audioPlayerStore.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Color.buttonSurface, in: Circle())
                    .foregroundStyle(Color.accentCinder)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(url.lastPathComponent)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let duration, duration > 0 {
                    Text(format(duration: duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(url.host(percentEncoded: false) ?? url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isCurrentPlaybackItem {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(Color.accentCinder)
            }
        }
        .padding(.vertical, 8)
    }

    private func format(duration: Int) -> String {
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var isCurrentPlaybackItem: Bool {
        audioPlayerStore.currentItem?.streamURL == url
    }
}

private struct NativeVideoPlayerCard: View {
    let url: URL

    var body: some View {
        AVPlayerContainer(url: url)
            .background(Color.buttonSurface)
    }
}

private struct AVPlayerContainer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        let currentURL = (controller.player?.currentItem?.asset as? AVURLAsset)?.url
        guard currentURL != url else { return }
        controller.player = AVPlayer(url: url)
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}

private struct YouTubeEmbeddedPlayer: UIViewRepresentable {
    let playerURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.loadHTMLString(embedHTML(for: playerURL), baseURL: URL(string: "https://www.youtube.com"))
        context.coordinator.loadedURL = playerURL
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != playerURL else { return }
        context.coordinator.loadedURL = playerURL
        webView.loadHTMLString(embedHTML(for: playerURL), baseURL: URL(string: "https://www.youtube.com"))
    }

    private func embedHTML(for url: URL) -> String {
        let embedURL = "\(url.absoluteString)?playsinline=1&rel=0&modestbranding=1&enablejsapi=1"
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
          <style>
            html, body {
              margin: 0;
              padding: 0;
              background: transparent;
              overflow: hidden;
              width: 100%;
              height: 100%;
            }
            iframe {
              border: 0;
              width: 100%;
              height: 100%;
            }
          </style>
        </head>
        <body>
          <iframe
            src="\(embedURL)"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
            allowfullscreen
            referrerpolicy="strict-origin-when-cross-origin">
          </iframe>
        </body>
        </html>
        """
    }

    final class Coordinator {
        var loadedURL: URL?
    }
}
