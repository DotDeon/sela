import AppKit
import ArcImport
import ArcSnapshot
import Foundation

let usage = """
Usage:
  brow-arc snapshot <destination-folder> [--allow-running]
  brow-arc inspect [--root <arc-or-snapshot-folder>]
"""

func fail(_ message: String, status: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(status)
}

func installedArcVersion() -> String? {
    let plist = URL(fileURLWithPath: "/Applications/Arc.app/Contents/Info.plist")
    guard let info = NSDictionary(contentsOf: plist) else { return nil }
    return info["CFBundleShortVersionString"] as? String
}

func runSnapshot(_ arguments: [String]) {
    var allowRunning = false
    var destination: String?
    for argument in arguments {
        if argument == "--allow-running" {
            allowRunning = true
        } else if destination == nil, !argument.hasPrefix("--") {
            destination = argument
        } else {
            fail(usage, status: 2)
        }
    }
    guard let destination else { fail(usage, status: 2) }

    let snapshotter = ArcSnapshotter(
        source: ArcDataLocation.live.root,
        destinationRoot: URL(fileURLWithPath: destination),
        arcVersion: installedArcVersion(),
        isArcRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: "company.thebrowser.Browser").isEmpty },
        availableCapacity: { url in
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        }
    )

    do {
        let result = try snapshotter.run(now: .now, allowWhileRunning: allowRunning)
        let gigabytes = Double(result.manifest.totalBytes) / 1_000_000_000
        print(result.folderURL.path)
        print("\(result.manifest.fileCount) files, \(String(format: "%.1f", gigabytes)) GB")
    } catch ArcSnapshotError.arcIsRunning {
        fail("Arc is running. Quit Arc first, or pass --allow-running.")
    } catch ArcSnapshotError.insufficientSpace(let needed, let available) {
        let gb = { (bytes: Int64) in String(format: "%.1f GB", Double(bytes) / 1_000_000_000) }
        fail("Not enough space: the snapshot needs \(gb(needed)) and the destination has \(gb(available)).")
    } catch ArcSnapshotError.sourceMissing(let url) {
        fail("No Arc data found at \(url.path).")
    } catch ArcSnapshotError.destinationExists(let url) {
        fail("\(url.path) already exists.")
    } catch {
        fail("Snapshot failed: \(error.localizedDescription)")
    }
}

func runInspect(_ arguments: [String]) {
    var location = ArcDataLocation.live
    switch arguments.count {
    case 0:
        break
    case 2 where arguments[0] == "--root":
        location = ArcDataLocation(root: URL(fileURLWithPath: arguments[1]))
    default:
        fail(usage, status: 2)
    }

    do {
        print(inspectReport(try ArcSidebarImporter().importSidebar(from: location.sidebarFileURL)))
    } catch ArcImportError.fileNotFound(let url) {
        fail("No Arc sidebar file at \(url.path).")
    } catch ArcImportError.noSpaces {
        fail("Arc's sidebar file has no spaces.")
    } catch ArcImportError.malformed(let detail) {
        fail("Arc's sidebar file couldn't be read: \(detail)")
    } catch {
        fail("Inspect failed: \(error.localizedDescription)")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "snapshot": runSnapshot(Array(arguments.dropFirst()))
case "inspect": runInspect(Array(arguments.dropFirst()))
default: fail(usage, status: 2)
}
