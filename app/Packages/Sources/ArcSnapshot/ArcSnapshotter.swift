import Foundation

public struct SnapshotResult: Sendable {
    public var folderURL: URL
    public var manifest: SnapshotManifest
}

public enum ArcSnapshotError: Error, Equatable, Sendable {
    case sourceMissing(URL)
    case arcIsRunning
    case insufficientSpace(needed: Int64, available: Int64)
    case destinationExists(URL)
}

/// Copies Arc's data folder, minus caches, into a dated folder. Never writes inside the source.
public struct ArcSnapshotter: Sendable {
    public static let excludedDirectoryNames: Set<String> = [
        "Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache",
        "GrShaderCache", "ShaderCache", "component_crx_cache", "Crashpad",
    ]

    let source: URL
    let destinationRoot: URL
    let arcVersion: String?
    let isArcRunning: @Sendable () -> Bool
    let availableCapacity: @Sendable (URL) throws -> Int64

    public init(
        source: URL,
        destinationRoot: URL,
        arcVersion: String?,
        isArcRunning: @escaping @Sendable () -> Bool,
        availableCapacity: @escaping @Sendable (URL) throws -> Int64
    ) {
        self.source = source
        self.destinationRoot = destinationRoot
        self.arcVersion = arcVersion
        self.isArcRunning = isArcRunning
        self.availableCapacity = availableCapacity
    }

    public func run(now: Date, allowWhileRunning: Bool = false) throws -> SnapshotResult {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ArcSnapshotError.sourceMissing(source)
        }
        guard allowWhileRunning || !isArcRunning() else { throw ArcSnapshotError.arcIsRunning }

        let folderURL = destinationRoot.appending(path: "Arc-snapshot-\(Self.timestamp(now))")
        guard !fm.fileExists(atPath: folderURL.path) else { throw ArcSnapshotError.destinationExists(folderURL) }

        let plan = try makePlan()
        let needed = (plan.totalBytes * 11 + 9) / 10
        let available = try availableCapacity(destinationRoot)
        guard available >= needed else { throw ArcSnapshotError.insufficientSpace(needed: needed, available: available) }

        let partialURL = destinationRoot.appending(path: folderURL.lastPathComponent + ".partial")
        do {
            try? fm.removeItem(at: partialURL)
            try copy(plan, to: partialURL)

            let manifest = SnapshotManifest(
                createdAt: Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down)),
                sourcePath: source.path,
                arcVersion: arcVersion,
                fileCount: plan.files.count,
                totalBytes: plan.totalBytes,
                skippedSpecialFiles: plan.skippedSpecialFiles
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(manifest).write(to: partialURL.appending(path: "snapshot-manifest.json"))

            try fm.moveItem(at: partialURL, to: folderURL)
            return SnapshotResult(folderURL: folderURL, manifest: manifest)
        } catch {
            try? fm.removeItem(at: partialURL)
            throw error
        }
    }

    // MARK: Planning

    private struct Plan {
        var directories: [String] = []
        var files: [String] = []
        var symlinks: [String] = []
        var totalBytes: Int64 = 0
        var skippedSpecialFiles = 0
    }

    /// Walks the source once so the space check happens before anything is written.
    /// Uses path-based enumeration so relative paths don't depend on how the source path resolves.
    private func makePlan() throws -> Plan {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: source.path) else {
            throw ArcSnapshotError.sourceMissing(source)
        }

        var plan = Plan()
        while let relative = enumerator.nextObject() as? String {
            // attributesOfItem doesn't follow symlinks, so a link reports as a link.
            let attributes = try fm.attributesOfItem(atPath: source.appending(path: relative).path)
            switch attributes[.type] as? FileAttributeType {
            case .typeSymbolicLink?:
                plan.symlinks.append(relative)
            case .typeDirectory?:
                if Self.excludedDirectoryNames.contains((relative as NSString).lastPathComponent) {
                    enumerator.skipDescendants()
                } else {
                    plan.directories.append(relative)
                }
            case .typeRegular?:
                plan.files.append(relative)
                plan.totalBytes += (attributes[.size] as? NSNumber)?.int64Value ?? 0
            default:
                plan.skippedSpecialFiles += 1
            }
        }
        return plan
    }

    private func copy(_ plan: Plan, to target: URL) throws {
        let fm = FileManager.default
        let root = source
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        for path in plan.directories {
            try fm.createDirectory(at: target.appending(path: path), withIntermediateDirectories: true)
        }
        for path in plan.files {
            try fm.copyItem(at: root.appending(path: path), to: target.appending(path: path))
        }
        for path in plan.symlinks {
            let destination = try fm.destinationOfSymbolicLink(atPath: root.appending(path: path).path)
            try fm.createSymbolicLink(atPath: target.appending(path: path).path, withDestinationPath: destination)
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
