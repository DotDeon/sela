import Foundation

/// Finds the extension inside what the user picked: a folder or an unpacked `.zip`.
public enum ExtensionSource {
    /// True for a `.zip` file, which is unpacked before installing.
    public static func isArchive(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "zip"
    }

    /// The folder holding `manifest.json`: `folder` itself, or the one folder inside it,
    /// which is how most `.zip` files of an extension unpack. Nil when there's no manifest.
    public static func manifestFolder(in folder: URL) -> URL? {
        if hasManifest(folder) { return folder }
        let children = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        let folders = children.filter { child in
            child.lastPathComponent != "__MACOSX" && (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        guard folders.count == 1, hasManifest(folders[0]) else { return nil }
        return folders[0]
    }

    /// Unpacks a `.zip` with the system's `ditto`.
    public static func unzip(_ archive: URL, into destination: URL) async throws {
        let status = try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archive.path, destination.path]
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }.value
        guard status == 0 else { throw ExtensionLibrary.InstallError.unreadableArchive }
    }

    private static func hasManifest(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: "manifest.json").path)
    }
}
