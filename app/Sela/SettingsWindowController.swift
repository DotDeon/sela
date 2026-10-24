import AppKit
import BrowserImport
import Browsing
import ContentBlocking
import History
import Sidebar
import SidebarModel
import SwiftUI

/// Sela > Settings… (Cmd+,): General, Ad Blocking, Permissions and Import.
@MainActor
final class SettingsWindowController: NSWindowController {
    /// `currentSpace` names the space imported bookmarks go into: the one shown in the frontmost browser window.
    init(
        contentBlocker: ContentBlocker?,
        history: HistoryStore?,
        sidebar: SidebarStore,
        currentSpace: @escaping () -> SpaceID?,
        onSettingsChanged: @escaping () -> Void
    ) {
        let view = SettingsView(contentBlocker: contentBlocker, history: history, sidebar: sidebar, currentSpace: currentSpace, onSettingsChanged: onSettingsChanged)
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
    let sidebar: SidebarStore
    let currentSpace: () -> SpaceID?
    let onSettingsChanged: () -> Void

    var body: some View {
        TabView {
            GeneralSettings(onSettingsChanged: onSettingsChanged).tabItem { Label("General", systemImage: "gearshape") }
            if let contentBlocker {
                AdBlockingSettings(blocker: contentBlocker).tabItem { Label("Ad Blocking", systemImage: "shield") }
            }
            PermissionSettings().tabItem { Label("Permissions", systemImage: "video") }
            ImportSettings(history: history, sidebar: sidebar, currentSpace: currentSpace).tabItem { Label("Import", systemImage: "square.and.arrow.down") }
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
    let sidebar: SidebarStore
    let currentSpace: () -> SpaceID?

    var body: some View {
        Form {
            BrowserImportSection(history: history, sidebar: sidebar, currentSpace: currentSpace)
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

/// Imports bookmarks and history from whichever of Chrome, Brave, Edge and Safari are on this Mac.
private struct BrowserImportSection: View {
    let history: HistoryStore?
    let sidebar: SidebarStore
    let currentSpace: () -> SpaceID?

    @State private var profiles: [BrowserProfile] = []
    @State private var browser: Browser?
    @State private var profileID: BrowserProfile.ID?
    @State private var isImporting = false
    @State private var result: String?
    @State private var needsFullDiskAccess = false

    private var browsers: [Browser] {
        Browser.allCases.filter { browser in profiles.contains { $0.browser == browser } }
    }

    private var browserProfiles: [BrowserProfile] {
        profiles.filter { $0.browser == browser }
    }

    private var chosen: BrowserProfile? {
        browserProfiles.first { $0.id == profileID } ?? browserProfiles.first
    }

    var body: some View {
        Section("From another browser") {
            if profiles.isEmpty {
                Text("Sela didn't find Chrome, Brave, Edge or Safari on this Mac.").foregroundStyle(.secondary)
            } else {
                Picker("Browser", selection: $browser) {
                    ForEach(browsers, id: \.self) { Text($0.name).tag(Optional($0)) }
                }
                .onChange(of: browser) { _, _ in
                    profileID = BrowserDataImport.mostLikely(among: browserProfiles)?.id
                    result = nil
                    needsFullDiskAccess = false
                }
                if browserProfiles.count > 1 {
                    Picker("Profile", selection: $profileID) {
                        ForEach(browserProfiles) { Text($0.name ?? $0.folder.lastPathComponent).tag(Optional($0.id)) }
                    }
                }
                HStack {
                    Text("Bookmarks, and history from the last 90 days")
                    Spacer()
                    if isImporting { ProgressView().controlSize(.small) }
                    Button("Import Bookmarks and History") { runImport() }.disabled(isImporting || chosen == nil)
                }
                if needsFullDiskAccess {
                    Text(BrowserDataImport.fullDiskAccessExplanation)
                    Button("Open Full Disk Access Settings") { BrowserDataImport.openFullDiskAccessSettings() }
                }
                if let result {
                    Text(result)
                }
                Text("Bookmarks become pinned tabs and folders in the space you're in. Anything already pinned there is skipped, and favourites aren't changed.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: reload)
    }

    /// Looks again each time, since a browser may have been installed or used since.
    private func reload() {
        profiles = BrowserLocations.live.profiles()
        if browser.map(browsers.contains) != true {
            browser = BrowserDataImport.mostLikely(among: profiles)?.browser
            profileID = BrowserDataImport.mostLikely(among: browserProfiles)?.id
        }
    }

    private func runImport() {
        guard let profile = chosen else { return }
        isImporting = true
        result = nil
        needsFullDiskAccess = false
        Task {
            do {
                let outcome = try await BrowserDataImport.run(profile, sidebar: sidebar, space: currentSpace(), history: history)
                result = BrowserDataImport.summary(outcome, from: profile.browser)
            } catch BrowserImportError.needsFullDiskAccess {
                needsFullDiskAccess = true
            } catch {
                result = "Sela couldn't read \(profile.browser.name)'s bookmarks and history. (\(error.localizedDescription))"
            }
            isImporting = false
        }
    }
}
