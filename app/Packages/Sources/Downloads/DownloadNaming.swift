import Foundation

/// Where a download called `filename` can go in `folder` without replacing anything: the name as it is,
/// or with " 2", " 3" and so on before the extension, as Safari does. Folder parts and leading dots are dropped,
/// and an empty name becomes "download".
public func availableDestination(for filename: String, in folder: URL, fileExists: (URL) -> Bool) -> URL {
    var name = (filename as NSString).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    while name.hasPrefix(".") { name.removeFirst() }
    if name.isEmpty || name == "/" { name = "download" }

    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var candidate = folder.appending(path: name)
    var number = 2
    while fileExists(candidate) {
        let numbered = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
        candidate = folder.appending(path: numbered)
        number += 1
    }
    return candidate
}

/// The file a download is written to until it finishes: the destination with ".download" added.
public func partialURL(for destination: URL) -> URL {
    destination.appendingPathExtension("download")
}
