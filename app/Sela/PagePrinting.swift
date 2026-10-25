import AppKit
import BrowserEngine
import Browsing
import UniformTypeIdentifiers

/// File > Print… and File > Export as PDF…, for the page in front of a window.
@MainActor
enum PagePrinting {
    /// Prints the page through the standard print panel, as a sheet on `window`.
    static func print(_ tab: (any BrowserTab)?, in window: NSWindow?) {
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        guard let tab, let window, let operation = tab.printOperation(with: info) else {
            NSSound.beep()
            return
        }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    /// Asks where to save, then writes the page as a PDF there.
    static func exportPDF(_ tab: (any BrowserTab)?, in window: NSWindow?) {
        guard let tab, let window, tab.state.url != nil else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = pdfFileName(for: tab.state)
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let destination = panel.url else { return }
            Task { @MainActor in
                do {
                    let data = try await tab.pdf()
                    try (data as NSData).write(to: destination, options: .atomic)
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Sela couldn't save the PDF"
                    alert.informativeText = error.localizedDescription
                    alert.beginSheetModal(for: window) { _ in }
                }
            }
        }
    }

    /// The page's title as a file name, without the characters file names can't have.
    static func pdfFileName(for state: TabState) -> String {
        let title = displayTitle(for: state)
        var name = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = "Page" }
        return String(name.prefix(200)) + ".pdf"
    }
}
