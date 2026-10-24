import Downloads
import Foundation

/// A free place for a download in `folder`, reserved so the next download with the same name gets another.
/// Taken means on disk, half-written, or promised to another download that hasn't written yet.
@MainActor
func reserveDownloadDestination(for suggestedFilename: String, in folder: URL, downloads: DownloadList?, reserved: inout Set<URL>) -> URL {
    let destination = availableDestination(for: suggestedFilename, in: folder) { [reserved] url in
        FileManager.default.fileExists(atPath: url.path) || FileManager.default.fileExists(atPath: partialURL(for: url).path)
            || downloads?.isReserved(url) == true || reserved.contains(url.standardizedFileURL)
    }
    downloads?.reserve(destination)
    reserved.insert(destination.standardizedFileURL)
    return destination
}
