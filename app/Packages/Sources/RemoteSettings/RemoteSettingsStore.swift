import Foundation

/// Downloads the remote settings once a day and keeps the last good copy, with its signature, in one folder,
/// so Sela uses it offline too. A copy only replaces the last one when it comes from Sela's website over https,
/// fits in 64 KB, carries a valid signature and reads as version 1.
@MainActor
public final class RemoteSettingsStore {
    public nonisolated static let address = URL(string: "https://dotdeon.github.io/sela/remote-settings.json")!
    public nonisolated static let maxSize = 64 * 1024
    static let maxSignatureSize = 1024

    /// What a download returned. `url` is where it ended up after redirects.
    public struct Download: Sendable {
        public let data: Data
        public let status: Int
        public let url: URL?

        public init(data: Data, status: Int, url: URL?) {
            self.data = data
            self.status = status
            self.url = url
        }
    }

    public private(set) var settings: RemoteSettings

    private let folder: URL
    private let signature: RemoteSettingsSignature
    private let now: @MainActor () -> Date
    private let fetch: @Sendable (URL) async throws -> Download
    private var checkedAt: Date?

    /// `fetch` stops reading once a body passes the size it's given.
    public init(
        folder: URL,
        signature: RemoteSettingsSignature,
        now: @escaping @MainActor () -> Date = { .now },
        fetch: @escaping @Sendable (URL) async throws -> Download = { try await RemoteSettingsStore.download($0, limit: RemoteSettingsStore.maxSize) }
    ) {
        self.folder = folder
        self.signature = signature
        self.now = now
        self.fetch = fetch
        let saved = try? Data(contentsOf: folder.appending(path: Self.settingsFileName))
        let savedSignature = try? Data(contentsOf: folder.appending(path: Self.signatureFileName))
        // Checked again in case the key changed since it was saved.
        settings = saved.flatMap { data in savedSignature.flatMap { Self.verified(data, signature: $0, with: signature) } } ?? .empty
        checkedAt = (try? Data(contentsOf: folder.appending(path: Self.checkedFileName))).flatMap { try? JSONDecoder().decode(Date.self, from: $0) }
    }

    static let settingsFileName = "remote-settings.json"
    static let signatureFileName = "remote-settings.json.sig"
    private static let checkedFileName = "checked.json"

    /// Downloads the file when it hasn't been checked for `maxAge`. Returns true when the settings changed.
    @discardableResult
    public func refresh(maxAge: TimeInterval = 86_400) async -> Bool {
        if let checkedAt, now().timeIntervalSince(checkedAt) < maxAge, now() >= checkedAt { return false }
        let signatureAddress = Self.address.deletingLastPathComponent().appending(path: Self.signatureFileName)
        // No answer at all, such as when offline, tries again next time.
        guard let file = try? await fetch(Self.address), let fileSignature = try? await fetch(signatureAddress) else { return false }
        markChecked()
        guard Self.isUsable(file, limit: Self.maxSize), Self.isUsable(fileSignature, limit: Self.maxSignatureSize),
              let fresh = Self.verified(file.data, signature: fileSignature.data, with: signature)
        else { return false }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? file.data.write(to: folder.appending(path: Self.settingsFileName), options: .atomic)
        try? fileSignature.data.write(to: folder.appending(path: Self.signatureFileName), options: .atomic)
        guard fresh != settings else { return false }
        settings = fresh
        return true
    }

    /// Only https from Sela's own website.
    nonisolated static func isAllowed(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host() == address.host() && url.port == nil && url.path().hasPrefix("/sela/")
    }

    private static func isUsable(_ download: Download, limit: Int) -> Bool {
        isAllowed(download.url) && download.status == 200 && download.data.count <= limit
    }

    private static func verified(_ data: Data, signature: Data, with key: RemoteSettingsSignature) -> RemoteSettings? {
        guard data.count <= maxSize, key.isValid(signature: signature, for: data) else { return nil }
        return RemoteSettings(json: data)
    }

    private func markChecked() {
        checkedAt = now()
        guard let data = try? JSONEncoder().encode(checkedAt) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appending(path: Self.checkedFileName), options: .atomic)
    }

    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    /// Reads at most one byte past `limit`, so an oversized body is noticed without downloading all of it.
    /// Refuses anything but https from Sela's website before sending the request.
    public nonisolated static func download(_ url: URL, limit: Int) async throws -> Download {
        guard isAllowed(url) else { throw URLError(.unsupportedURL) }
        let (bytes, response) = try await session.bytes(from: url)
        let http = response as? HTTPURLResponse
        var data = Data()
        if response.expectedContentLength <= Int64(limit) {
            for try await byte in bytes {
                data.append(byte)
                if data.count > limit { break }
            }
        } else {
            data = Data(count: limit + 1)
        }
        bytes.task.cancel()
        return Download(data: data, status: http?.statusCode ?? 0, url: http?.url)
    }
}
