import AppKit
import BrowserEngine

/// The sheets a page can ask for, shared by main and Little Sela windows.
@MainActor
enum PagePrompts {
    /// Files for an upload. Nil means cancelled.
    static func chooseFiles(in window: NSWindow?, multiple: Bool, folders: Bool) async -> [URL]? {
        guard let window else { return nil }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = folders
        panel.canChooseFiles = true
        return await panel.beginSheetModal(for: window) == .OK ? panel.urls : nil
    }

    /// Whether a site may use the camera or microphone.
    static func askToCapture(_ media: MediaCapture, origin: URL, in window: NSWindow?) async -> Bool {
        guard let window else { return false }
        let what = switch media {
        case .camera: "camera"
        case .microphone: "microphone"
        case .cameraAndMicrophone: "camera and microphone"
        }
        let alert = NSAlert()
        alert.messageText = "Allow \(origin.host() ?? "this site") to use your \(what)?"
        alert.informativeText = "Sela remembers your choice for this site."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don't Allow")
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }
}
