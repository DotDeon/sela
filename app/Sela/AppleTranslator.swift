import AppKit
import PageTranslation
import SwiftUI
import Translation

/// Translates on the Mac with Apple's Translation framework, so no page text leaves the computer.
///
/// The framework hands out a `TranslationSession` only to a SwiftUI view, through `translationTask`, so each
/// language pair gets a hidden hosting view in the browser window that waits for jobs and runs them in its
/// session. Keeping the view in the window also gives the framework's download prompt a window to attach to.
@MainActor
final class AppleTranslator: Translator {
    private weak var host: NSView?
    private var sessions: [Pair: SessionHost] = [:]

    /// `host` is the view the hidden session views live in, so it should be in the window for as long as the window.
    init(host: NSView) {
        self.host = host
    }

    func availability(from source: Locale.Language, to target: Locale.Language) async -> TranslationAvailability {
        switch await Self.status(from: source, to: target) {
        case .installed: .installed
        case .supported: .supported
        case .unsupported: .unsupported
        @unknown default: .unsupported
        }
    }

    func prepare(from source: Locale.Language, to target: Locale.Language) async throws {
        try await session(from: source, to: target).run { session in
            try await session.prepareTranslation()
        }
    }

    func translate(_ texts: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String] {
        try await session(from: source, to: target).run { session in
            // Each request carries its place in the list, since answers can come back in any order.
            let requests = texts.enumerated().map { TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset)) }
            var translated = texts
            for response in try await session.translations(from: requests) {
                guard let identifier = response.clientIdentifier, let index = Int(identifier), texts.indices.contains(index) else { continue }
                translated[index] = response.targetText
            }
            return translated
        }
    }

    func supportedLanguages() async -> [Locale.Language] {
        await Self.supportedTargetLanguages()
    }

    /// Every language the Mac can translate pages into, in the order the framework lists them.
    nonisolated static func supportedTargetLanguages() async -> [Locale.Language] {
        await LanguageAvailability().supportedLanguages
    }

    nonisolated private static func status(from source: Locale.Language, to target: Locale.Language) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: source, to: target)
    }

    private func session(from source: Locale.Language, to target: Locale.Language) throws -> SessionHost {
        let pair = Pair(source: source.minimalIdentifier, target: target.minimalIdentifier)
        if let existing = sessions[pair] { return existing }
        guard let host else { throw TranslationUnavailable() }
        let session = SessionHost(source: source, target: target)
        session.view.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        session.view.alphaValue = 0
        host.addSubview(session.view, positioned: .below, relativeTo: nil)
        sessions[pair] = session
        return session
    }

    private struct Pair: Hashable {
        var source: String
        var target: String
    }
}

struct TranslationUnavailable: Error {}

/// One language pair's hidden view and the jobs waiting for its session.
@MainActor
private final class SessionHost {
    let view: NSView
    private let queue = JobQueue()

    init(source: Locale.Language, target: Locale.Language) {
        let configuration = TranslationSession.Configuration(source: source, target: target)
        view = NSHostingView(rootView: SessionView(configuration: configuration, queue: queue))
    }

    /// Runs `body` with the pair's session once the framework provides one.
    func run<Result: Sendable>(_ body: @escaping @Sendable (TranslationSession) async throws -> Result) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            queue.add { session in
                do {
                    continuation.resume(returning: try await body(session))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Jobs for a session, handed out one at a time to whoever is waiting for them.
@MainActor
private final class JobQueue {
    typealias Job = @Sendable (TranslationSession) async -> Void
    private var jobs: [Job] = []
    private var waiter: CheckedContinuation<Job, Never>?

    func add(_ job: @escaping Job) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: job)
        } else {
            jobs.append(job)
        }
    }

    func next() async -> Job {
        if !jobs.isEmpty { return jobs.removeFirst() }
        return await withCheckedContinuation { waiter = $0 }
    }
}

/// Nothing to see: it exists for `translationTask`, which keeps its session for as long as the task runs.
private struct SessionView: View {
    let configuration: TranslationSession.Configuration
    let queue: JobQueue

    var body: some View {
        Color.clear
            .translationTask(configuration) { @Sendable session in
                while !Task.isCancelled {
                    let job = await queue.next()
                    await job(session)
                }
            }
    }
}
