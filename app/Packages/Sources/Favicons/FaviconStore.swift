import AppKit
import Foundation
import Observation

/// Site icons, cached in memory and on disk by host. Icons come only from the site itself.
@MainActor
@Observable
public final class FaviconStore {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    /// Icons larger than this are ignored.
    nonisolated static let maximumBytes = 512 * 1024

    private var images: [String: NSImage] = [:]

    @ObservationIgnored private let cacheFolder: URL
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private var inFlight: Set<String> = []
    /// Hosts with no usable icon this launch. Not retried until Sela restarts.
    @ObservationIgnored private var failed: Set<String> = []
    /// Hosts whose icon isn't on disk, so the sidebar's many lookups don't each try the file again.
    @ObservationIgnored private var notOnDisk: Set<String> = []
    /// The icon each host's pages last declared, so repeated reports don't refetch it.
    @ObservationIgnored private var rememberedIcons: [String: URL] = [:]

    public init(cacheFolder: URL, fetch: @escaping Fetch = FaviconStore.urlSessionFetch) {
        self.cacheFolder = cacheFolder
        self.fetch = fetch
    }

    /// `~/Library/Application Support/Sela/Favicons`, created if needed.
    public static func defaultCacheFolder() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = support.appending(path: "Sela/Favicons", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The icon for a page's site. On a miss, fetches `/favicon.ico` in the background and returns nil;
    /// views reading this update when the icon arrives.
    public func image(forPage url: URL?) -> NSImage? {
        guard let url, let host = Self.cacheKey(for: url) else { return nil }
        if let image = images[host] { return image }
        if !notOnDisk.contains(host) {
            if let image = NSImage(contentsOf: fileURL(for: host)) {
                images[host] = image
                return image
            }
            notOnDisk.insert(host)
        }
        if !inFlight.contains(host), !failed.contains(host), let iconURL = Self.faviconICO(for: url) {
            load(iconURL, for: host)
        }
        return nil
    }

    /// Fetches the icon a page declared and uses it for the page's site from now on.
    /// Reporting the same icon again does nothing.
    public func remember(iconURL: URL, forPage url: URL) {
        guard let scheme = iconURL.scheme?.lowercased(), ["http", "https", "data"].contains(scheme),
              let host = Self.cacheKey(for: url), rememberedIcons[host] != iconURL
        else { return }
        rememberedIcons[host] = iconURL
        failed.remove(host)
        load(iconURL, for: host)
    }

    /// Fetches with no cookies, giving up after 15 seconds or past 512 KB.
    public static let urlSessionFetch: Fetch = sessionFetch(using: session)

    /// A fetch on `session` that streams the response and stops as soon as it passes 512 KB,
    /// so a page can't make Sela download without limit.
    public nonisolated static func sessionFetch(using session: URLSession) -> Fetch {
        { url in
            let (bytes, response) = try await session.bytes(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > maximumBytes {
                    bytes.task.cancel()
                    throw URLError(.dataLengthExceedsMaximum)
                }
            }
            return data
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()

    // MARK: Loading

    private func load(_ iconURL: URL, for host: String) {
        inFlight.insert(host)
        let fetch = fetch
        Task {
            let data = try? await fetch(iconURL)
            inFlight.remove(host)
            guard let data, let image = Self.validImage(from: data) else {
                if images[host] == nil { failed.insert(host) }
                return
            }
            images[host] = image
            save(image, for: host)
        }
    }

    private func save(_ image: NSImage, for host: String) {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: fileURL(for: host), options: .atomic)
    }

    private func fileURL(for host: String) -> URL {
        let safe = host.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return cacheFolder.appending(path: "\(safe).png")
    }

    private static func validImage(from data: Data) -> NSImage? {
        guard data.count <= maximumBytes, let image = NSImage(data: data), image.isValid,
              image.size.width > 0, image.size.height > 0
        else { return nil }
        return image
    }

    /// The lower-cased host of an http or https page.
    private static func cacheKey(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host()?.lowercased(), !host.isEmpty
        else { return nil }
        return host
    }

    private static func faviconICO(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
