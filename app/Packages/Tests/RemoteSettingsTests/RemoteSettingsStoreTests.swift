import CryptoKit
import Foundation
import Testing
@testable import RemoteSettings

private let signingKey = Curve25519.Signing.PrivateKey()
private let key = RemoteSettingsSignature(publicKey: signingKey.publicKey.rawRepresentation.base64EncodedString())!

private func sign(_ data: Data, with privateKey: Curve25519.Signing.PrivateKey = signingKey) -> Data {
    Data(try! privateKey.signature(for: data).base64EncodedString().utf8)
}

private let goodFile = Data(#"{ "version": 1, "features": { "newThing": true } }"#.utf8)
private let signatureAddress = URL(string: "https://dotdeon.github.io/sela/remote-settings.json.sig")!

private func freshFolder() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "sela-remote-\(UUID().uuidString)", directoryHint: .isDirectory)
}

/// Answers the settings file and its signature, each from where it was asked for unless `finalURL` says otherwise.
private func serving(_ file: Data, signature: Data, status: Int = 200, finalURL: URL? = nil, counter: Counter? = nil) -> @Sendable (URL) async throws -> RemoteSettingsStore.Download {
    { url in
        counter?.add()
        let body = url.lastPathComponent.hasSuffix(".sig") ? signature : file
        return RemoteSettingsStore.Download(data: body, status: status, url: finalURL ?? url)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

@Test func signaturesFromTheKeyAreValid() {
    #expect(key.isValid(signature: sign(goodFile), for: goodFile))
    #expect(key.isValid(signature: Data((String(data: sign(goodFile), encoding: .utf8)! + "\n").utf8), for: goodFile))
}

@Test func badSignaturesAreRefused() {
    var tampered = goodFile
    tampered[tampered.startIndex] = UInt8(ascii: "[")
    #expect(!key.isValid(signature: sign(goodFile), for: tampered))
    #expect(!key.isValid(signature: sign(goodFile, with: Curve25519.Signing.PrivateKey()), for: goodFile))
    #expect(!key.isValid(signature: Data("not base64".utf8), for: goodFile))
    #expect(!key.isValid(signature: Data(Data(count: 10).base64EncodedString().utf8), for: goodFile))
}

@Test func thePlaceholderKeyTurnsRemoteSettingsOff() {
    #expect(RemoteSettingsSignature(publicKey: RemoteSettingsSignature.placeholderKey) == nil)
    #expect(RemoteSettingsSignature(publicKey: "abc") == nil)
}

@Test func onlyHttpsFromSelasWebsiteIsAllowed() {
    #expect(RemoteSettingsStore.isAllowed(RemoteSettingsStore.address))
    #expect(RemoteSettingsStore.isAllowed(signatureAddress))
    #expect(!RemoteSettingsStore.isAllowed(URL(string: "http://dotdeon.github.io/sela/remote-settings.json")))
    #expect(!RemoteSettingsStore.isAllowed(URL(string: "https://evil.github.io/sela/remote-settings.json")))
    #expect(!RemoteSettingsStore.isAllowed(URL(string: "https://dotdeon.github.io.evil.com/sela/remote-settings.json")))
    #expect(!RemoteSettingsStore.isAllowed(URL(string: "https://dotdeon.github.io:8443/sela/remote-settings.json")))
    #expect(!RemoteSettingsStore.isAllowed(URL(string: "https://dotdeon.github.io/other/remote-settings.json")))
    #expect(!RemoteSettingsStore.isAllowed(nil))
}

@MainActor
@Test func aSignedFileIsUsedAndCached() async {
    let folder = freshFolder()
    let store = RemoteSettingsStore(folder: folder, signature: key, fetch: serving(goodFile, signature: sign(goodFile)))
    #expect(store.settings == .empty)
    #expect(await store.refresh())
    #expect(store.settings.features == ["newThing": true])

    // Offline, the next launch starts from the saved copy.
    let offline = RemoteSettingsStore(folder: folder, signature: key, fetch: { _ in throw URLError(.notConnectedToInternet) })
    #expect(offline.settings.features == ["newThing": true])
}

@MainActor
@Test func aBadSignatureKeepsTheLastGoodCopy() async {
    let folder = freshFolder()
    let first = RemoteSettingsStore(folder: folder, signature: key, fetch: serving(goodFile, signature: sign(goodFile)))
    await first.refresh()

    let evil = Data(#"{ "version": 1, "searchEngines": [{ "id": "google", "name": "Google", "template": "https://evil.example/?q=%s" }] }"#.utf8)
    let forged = RemoteSettingsStore(folder: folder, signature: key, fetch: serving(evil, signature: sign(evil, with: Curve25519.Signing.PrivateKey())))
    #expect(!(await forged.refresh(maxAge: 0)))
    #expect(forged.settings.features == ["newThing": true])
    #expect(forged.settings.searchEngines.isEmpty)
    #expect(RemoteSettingsStore(folder: folder, signature: key).settings.features == ["newThing": true])
}

@MainActor
@Test func aCachedCopyThatNoLongerVerifiesIsIgnored() async {
    let folder = freshFolder()
    await RemoteSettingsStore(folder: folder, signature: key, fetch: serving(goodFile, signature: sign(goodFile))).refresh()
    let otherKey = RemoteSettingsSignature(publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString())!
    #expect(RemoteSettingsStore(folder: folder, signature: otherKey).settings == .empty)
}

@MainActor
@Test func oversizedFilesAreRefused() async {
    let padding = String(repeating: " ", count: RemoteSettingsStore.maxSize)
    let big = Data(#"{ "version": 1, "features": { "newThing": true } \#(padding)}"#.utf8)
    let store = RemoteSettingsStore(folder: freshFolder(), signature: key, fetch: serving(big, signature: sign(big)))
    #expect(!(await store.refresh()))
    #expect(store.settings == .empty)
}

@MainActor
@Test func filesFromElsewhereOrFailedRequestsAreRefused() async {
    let redirected = RemoteSettingsStore(folder: freshFolder(), signature: key, fetch: serving(
        goodFile, signature: sign(goodFile), finalURL: URL(string: "https://evil.example/sela/remote-settings.json")
    ))
    #expect(!(await redirected.refresh()))
    let missing = RemoteSettingsStore(folder: freshFolder(), signature: key, fetch: serving(goodFile, signature: sign(goodFile), status: 404))
    #expect(!(await missing.refresh()))
    #expect(missing.settings == .empty)
}

@MainActor
@Test func checksOnceADay() async {
    let counter = Counter()
    var time = Date(timeIntervalSince1970: 1_000_000)
    let store = RemoteSettingsStore(folder: freshFolder(), signature: key, now: { time }, fetch: serving(goodFile, signature: sign(goodFile), counter: counter))
    await store.refresh()
    #expect(counter.count == 2)
    time += 3600
    await store.refresh()
    #expect(counter.count == 2)
    time += 86_400
    await store.refresh()
    #expect(counter.count == 4)
}

@MainActor
@Test func noAnswerTriesAgainNextTime() async {
    let counter = Counter()
    let store = RemoteSettingsStore(folder: freshFolder(), signature: key, fetch: { _ in
        counter.add()
        throw URLError(.notConnectedToInternet)
    })
    await store.refresh()
    await store.refresh()
    #expect(counter.count == 2)
}

@Test func downloadsRefuseOtherAddressesBeforeAsking() async {
    await #expect(throws: URLError.self) {
        try await RemoteSettingsStore.download(URL(string: "http://dotdeon.github.io/sela/remote-settings.json")!, limit: 10)
    }
}
