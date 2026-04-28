import Combine
import CryptoKit
import SwiftUI
import UIKit

struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder private let content: (Image) -> Content
    @ViewBuilder private let placeholder: () -> Placeholder

    @StateObject private var loader = CachedRemoteImageLoader()

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
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
            await loader.load(from: url)
        }
    }
}

@MainActor
private final class CachedRemoteImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    func load(from url: URL?) async {
        guard let url else {
            image = nil
            return
        }

        do {
            image = try await RemoteImageCache.shared.image(for: url)
        } catch {
            image = nil
        }
    }
}

actor RemoteImageCache {
    static let shared = RemoteImageCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectoryURL: URL?

    init() {
        if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let directoryURL = cachesURL.appendingPathComponent("RemoteImageCache", isDirectory: true)
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            cacheDirectoryURL = directoryURL
        } else {
            cacheDirectoryURL = nil
        }
    }

    func image(for url: URL) async throws -> UIImage {
        let cacheKey = url.absoluteString as NSString

        if let cachedImage = memoryCache.object(forKey: cacheKey) {
            return cachedImage
        }

        if let diskImage = loadImageFromDisk(for: url) {
            memoryCache.setObject(diskImage, forKey: cacheKey)
            return diskImage
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }

        memoryCache.setObject(image, forKey: cacheKey)
        persist(data: data, for: url)
        return image
    }

    private func loadImageFromDisk(for url: URL) -> UIImage? {
        guard let fileURL = fileURL(for: url),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }

        return image
    }

    private func persist(data: Data, for url: URL) {
        guard let fileURL = fileURL(for: url) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func fileURL(for url: URL) -> URL? {
        guard let cacheDirectoryURL else { return nil }
        let fileName = sha256(url.absoluteString) + ".cache"
        return cacheDirectoryURL.appendingPathComponent(fileName)
    }

    private func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

actor RemoteFileCache {
    static let shared = RemoteFileCache()

    private let fileManager = FileManager.default
    private let cacheDirectoryURL: URL?

    init() {
        if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let directoryURL = cachesURL.appendingPathComponent("RemoteFileCache", isDirectory: true)
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            cacheDirectoryURL = directoryURL
        } else {
            cacheDirectoryURL = nil
        }
    }

    func localFileURL(for remoteURL: URL, preferredFileName: String) async throws -> URL {
        guard let cacheDirectoryURL else {
            throw URLError(.cannotCreateFile)
        }

        let fallbackExtension = URL(fileURLWithPath: preferredFileName).pathExtension
        let pathExtension = remoteURL.pathExtension.isEmpty ? fallbackExtension : remoteURL.pathExtension
        let fileName = sha256(remoteURL.absoluteString) + (pathExtension.isEmpty ? "" : ".\(pathExtension)")
        let localURL = cacheDirectoryURL.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: localURL.path) {
            return localURL
        }

        let (downloadedURL, _) = try await URLSession.shared.download(from: remoteURL)
        if fileManager.fileExists(atPath: localURL.path) {
            try? fileManager.removeItem(at: localURL)
        }
        try fileManager.moveItem(at: downloadedURL, to: localURL)
        return localURL
    }

    private func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
