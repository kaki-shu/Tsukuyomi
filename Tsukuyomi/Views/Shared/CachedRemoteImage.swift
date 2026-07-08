import SwiftUI
import UIKit

struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @StateObject private var loader: RemoteImageLoader

    init(
        url: URL,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        _loader = StateObject(wrappedValue: RemoteImageLoader(url: url))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loader.load()
        }
    }
}

@MainActor
final class RemoteImageLoader: ObservableObject {
    @Published var image: UIImage?
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func load() async {
        if let cached = await RemoteImageCache.shared.image(for: url) {
            image = cached
            return
        }

        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 60)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let image = UIImage(data: data) else { return }
            await RemoteImageCache.shared.store(data: data, image: image, for: url)
            URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
            self.image = image
        } catch {
            await RemoteImageCache.shared.markFailure(for: url)
            return
        }
    }

    static func configureSharedCache() {
        let diskCapacity = 512 * 1024 * 1024
        let memoryCapacity = 64 * 1024 * 1024
        let current = URLCache.shared
        guard current.diskCapacity < diskCapacity || current.memoryCapacity < memoryCapacity else { return }
        URLCache.shared = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity)
    }
}

actor RemoteImageCache {
    static let shared = RemoteImageCache()

    private let memoryCache = NSCache<NSURL, UIImage>()
    private var failedLookups: Set<String> = []
    private let cacheDirectory: URL

    init() {
        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        cacheDirectory = baseDirectory.appendingPathComponent("TsukuyomiImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func image(for url: URL) -> UIImage? {
        let key = cacheKey(for: url)
        if failedLookups.contains(key) {
            return nil
        }
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached
        }

        let fileURL = cacheFileURL(for: url)
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        memoryCache.setObject(image, forKey: url as NSURL)
        return image
    }

    func store(data: Data, image: UIImage, for url: URL) {
        let key = cacheKey(for: url)
        failedLookups.remove(key)
        memoryCache.setObject(image, forKey: url as NSURL)
        try? data.write(to: cacheFileURL(for: url), options: .atomic)
    }

    func markFailure(for url: URL) {
        failedLookups.insert(cacheKey(for: url))
    }

    private func cacheFileURL(for url: URL) -> URL {
        cacheDirectory.appendingPathComponent(cacheKey(for: url))
    }

    private func cacheKey(for url: URL) -> String {
        let source = Data(url.absoluteString.utf8)
        return source.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }
}
