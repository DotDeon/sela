import AppKit
import Browsing
import ContentBlocking
import Extensions
import History
import SwiftUI

/// Sela > Settings… (Cmd+,): General, Ad Blocking, Extensions, Permissions and Import.
@MainActor
final class SettingsWindowController: NSWindowController {
    init(contentBlocker: ContentBlocker?, history: HistoryStore?, extensions: ExtensionsController?, onSettingsChanged: @escaping () -> Void) {
        let view = SettingsView(contentBlocker: contentBlocker, history: history, extensions: extensions, onSettingsChanged: onSettingsChanged)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 420))
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

private struct SettingsView: View {
    let contentBlocker: ContentBlocker?
    let history: HistoryStore?
    let extensions: ExtensionsController?
    let onSettingsChanged: () -> Void

    var body: some View {
        TabView {
            GeneralSettings(onSettingsChanged: onSettingsChanged).tabItem { Label("General", systemImage: "gearshape") }
            if let contentBlocker {
                AdBlockingSettings(blocker: contentBlocker).tabItem { Label("Ad Blocking", systemImage: "shield") }
            }
            if let extensions {
                ExtensionSettings(controller: extensions).tabItem { Label("Extensions", systemImage: "puzzlepiece.extension") }
            }
            PermissionSettings().tabItem { Label("Permissions", systemImage: "video") }
            ImportSettings(history: history).tabItem { Label("Import", systemImage: "square.and.arrow.down") }
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }
}

private struct GeneralSettings: View {
    let onSettingsChanged: () -> Void
    @State private var sleepMinutes = TabSleepSettings().minutes
    @State private var archiveHours = ArchiveSweeper.hours
    @State private var isDefault = GeneralSettings.brIsDefault()

    var body: some View {
        Form {
            HStack {
                Text(isDefault ? "Sela is your default browser" : "Sela isn't your default browser")
                Spacer()
                if !isDefault {
                    Button("Make Default") { makeDefault() }
                }
            }
            Picker("Sleep unused tabs after", selection: $sleepMinutes) {
                Text("5 minutes").tag(5)
                Text("15 minutes").tag(15)
                Text("1 hour").tag(60)
                Text("Never").tag(0)
            }
            .onChange(of: sleepMinutes) { _, value in
                TabSleepSettings().minutes = value
                onSettingsChanged()
            }
            Picker("Archive unpinned tabs after", selection: $archiveHours) {
                ForEach(ArchiveSweeper.choices, id: \.self) { hours in
                    Text(hours == 0 ? "Never" : hours % 24 == 0 && hours >= 48 ? "\(hours / 24) days" : "\(hours) hours").tag(hours)
                }
            }
            .onChange(of: archiveHours) { _, value in
                ArchiveSweeper.hours = value
                onSettingsChanged()
            }
        }
        .formStyle(.grouped)
        // The window is reused, so read the choices again each time it shows: menus may have changed them.
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
    }

    private func reload() {
        sleepMinutes = TabSleepSettings().minutes
        archiveHours = ArchiveSweeper.hours
        isDefault = Self.brIsDefault()
    }

    private static func brIsDefault() -> Bool {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else { return false }
        return app.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    private func makeDefault() {
        Task {
            for scheme in ["http", "https"] {
                try? await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
            }
            isDefault = Self.brIsDefault()
        }
    }
}

private struct AdBlockingSettings: View {
    let blocker: ContentBlocker

    var body: some View {
        Form {
            Toggle("Block ads and trackers", isOn: Binding(get: { blocker.isEnabled }, set: { blocker.setEnabled($0) }))
            Section("Turned off on these sites") {
                if blocker.offSites.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                }
                ForEach(blocker.offSites.sorted(), id: \.self) { site in
                    HStack {
                        Text(site)
                        Spacer()
                        Button("Turn Back On") { blocker.setBlocking(true, forSite: site) }
                    }
                }
            }
            Text("Changes apply the next time a page on that site loads.").font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct ExtensionSettings: View {
    let controller: ExtensionsController
    private var library: ExtensionLibrary { controller.library }

    var body: some View {
        Form {
            if library.loadProblem != nil {
                Text("Sela couldn't read your list of extensions, so it isn't running them and won't change the list. Check the file Extensions.json in Sela's data folder.")
                    .foregroundStyle(.red)
            }
            Section("Installed") {
                if library.entries.isEmpty {
                    Text("No extensions yet").foregroundStyle(.secondary)
                }
                ForEach(library.entries) { entry in
                    row(entry)
                }
            }
            HStack {
                Spacer()
                Button("Add Extension…") { controller.chooseAndInstall(window: NSApp.keyWindow) }
                    .disabled(library.loadProblem != nil)
            }
            Text("Sela adds Web Extensions, the kind Safari and Chrome use, from a folder or a .zip file on your Mac. It can't install from the Chrome Web Store or the App Store, so download or unpack the extension first. Extensions that need a companion app, like some password managers, may not work yet.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func row(_ entry: ExtensionLibrary.Entry) -> some View {
        HStack(spacing: 10) {
            if let icon = entry.loaded?.icon(size: 32) {
                Image(nsImage: icon).resizable().frame(width: 24, height: 24)
            } else {
                Image(systemName: "puzzlepiece.extension").frame(width: 24, height: 24).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading) {
                Text(entry.record.name)
                if let problem = entry.problem {
                    Text(problem).font(.footnote).foregroundStyle(.red)
                } else if let version = entry.record.version {
                    Text("Version \(version)").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let options = entry.loaded?.optionsPageURL {
                Button("Options") { controller.openOptions(options) }
            }
            Button("Remove") { controller.confirmRemove(entry.id, window: NSApp.keyWindow) }
            Toggle("Turn on \(entry.record.name)", isOn: Binding(
                get: { entry.record.isEnabled },
                set: { on in Task { await library.setEnabled(on, for: entry.id) } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }
}

private struct PermissionSettings: View {
    @State private var sites = SitePermissions().sites()

    var body: some View {
        Form {
            Section("Camera and microphone") {
                if sites.isEmpty {
                    Text("No site has asked yet").foregroundStyle(.secondary)
                }
                ForEach(sites, id: \.site) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.site)
                            Text(describe(entry)).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Forget") {
                            SitePermissions().forget(site: entry.site)
                            sites = SitePermissions().sites()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { sites = SitePermissions().sites() }
    }

    private func describe(_ entry: (site: String, camera: Bool?, microphone: Bool?)) -> String {
        func word(_ choice: Bool?) -> String? { choice.map { $0 ? "allowed" : "blocked" } }
        return [word(entry.camera).map { "Camera \($0)" }, word(entry.microphone).map { "Microphone \($0)" }]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

private struct ImportSettings: View {
    let history: HistoryStore?

    var body: some View {
        Form {
            Section("From Arc") {
                HStack {
                    Text("Your browsing history from the last 90 days")
                    Spacer()
                    Button("Import History") { HistoryImport.runAndReport(into: history, window: NSApp.keyWindow) }
                }
                Text("Your Arc sidebar is imported the first time Sela opens. Importing again would replace your Sela sidebar, so it isn't offered here.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
