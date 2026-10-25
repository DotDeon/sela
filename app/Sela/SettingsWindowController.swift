import AppKit
import BrowserImport
import Browsing
import ContentBlocking
import Extensions
import History
import Passkeys
import Sidebar
import SidebarModel
import SwiftUI

/// Sela > Settings… (Cmd+,): General, Ad Blocking, Extensions, Passwords, Profiles, Permissions and Import.
/// Passwords shows only in a copy of Sela signed with the browser passkey entitlement.
@MainActor
final class SettingsWindowController: NSWindowController {
    /// `currentSpace` names the space imported bookmarks go into: the one shown in the frontmost browser window.
    /// `onDeleteProfile` deletes a profile the user has confirmed deleting, and its website data.
    init(
        contentBlocker: ContentBlocker?,
        history: HistoryStore?,
        sidebar: SidebarStore,
        extensions: ExtensionsController?,
        passkeys: PasskeyAccessModel?,
        currentSpace: @escaping () -> SpaceID?,
        onDeleteProfile: @escaping (ProfileID) -> Void,
        onSettingsChanged: @escaping () -> Void
    ) {
        let view = SettingsView(contentBlocker: contentBlocker, history: history, sidebar: sidebar, currentSpace: currentSpace, extensions: extensions,
                                passkeys: passkeys,
                                onDeleteProfile: onDeleteProfile, onSettingsChanged: onSettingsChanged)
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
    let extensions: ExtensionsController?
    let passkeys: PasskeyAccessModel?
    let onDeleteProfile: (ProfileID) -> Void
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
            if let passkeys {
                PasswordSettings(passkeys: passkeys).tabItem { Label("Passwords", systemImage: "key") }
            }
            ProfileSettings(sidebar: sidebar, onDelete: onDeleteProfile).tabItem { Label("Profiles", systemImage: "person.2") }
            PermissionSettings().tabItem { Label("Permissions", systemImage: "video") }
            ImportSettings(history: history, sidebar: sidebar, currentSpace: currentSpace).tabItem { Label("Import", systemImage: "square.and.arrow.down") }
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }
}

private struct GeneralSettings: View {
    let onSettingsChanged: () -> Void
    @State private var searchEngine = SearchEngineSettings().engine.id
    @State private var searchEngines = SearchEngineSettings().available
    @State private var sleepMinutes = TabSleepSettings().minutes
    @State private var archiveHours = ArchiveSweeper.hours
    @State private var isDefault = GeneralSettings.brIsDefault()
    @State private var linkDestination = ExternalLinkSettings().destination
    @State private var floatsVideos = PictureInPictureSettings().isEnabled

    var body: some View {
        Form {
            HStack {
                Text(isDefault ? "Sela is your default browser" : "Sela isn't your default browser")
                Spacer()
                if !isDefault {
                    Button("Make Default") { makeDefault() }
                }
            }
            Picker("Search engine", selection: $searchEngine) {
                ForEach(searchEngines, id: \.id) { engine in
                    Text(engine.name).tag(engine.id)
                }
            }
            .onChange(of: searchEngine) { _, value in
                guard let engine = searchEngines.first(where: { $0.id == value }) else { return }
                SearchEngineSettings().engine = engine
            }
            Picker("Open links from other apps in", selection: $linkDestination) {
                Text("Little Sela").tag(ExternalLinkDestination.littleWindow)
                Text("A new tab").tag(ExternalLinkDestination.newTab)
            }
            .onChange(of: linkDestination) { _, value in ExternalLinkSettings().destination = value }
            Toggle("Move playing videos to picture in picture when you switch away", isOn: $floatsVideos)
                .onChange(of: floatsVideos) { _, value in PictureInPictureSettings().isEnabled = value }
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
        searchEngines = SearchEngineSettings().available
        searchEngine = SearchEngineSettings().engine.id
        sleepMinutes = TabSleepSettings().minutes
        archiveHours = ArchiveSweeper.hours
        isDefault = Self.brIsDefault()
        linkDestination = ExternalLinkSettings().destination
        floatsVideos = PictureInPictureSettings().isEnabled
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

/// Passkey access, for a copy of Sela signed with the browser passkey entitlement.
private struct PasswordSettings: View {
    let passkeys: PasskeyAccessModel

    var body: some View {
        Form {
            Section("Passkeys") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Passkey access")
                        Text(passkeys.status).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if passkeys.isRequesting { ProgressView().controlSize(.small) }
                    if let action = passkeys.action {
                        Button(action.title) { perform(action) }.disabled(passkeys.isRequesting)
                    }
                }
                Text(passkeys.explanation).font(.footnote).foregroundStyle(.secondary)
            }
            Section("Saved passwords") {
                Text("Sela can't fill in passwords from the Passwords app yet, because macOS only offers them to Safari. Copy them from the Passwords app, or add your password manager's Web Extension in Extensions.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { passkeys.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in passkeys.refresh() }
    }

    private func perform(_ action: PasskeyAccessModel.Action) {
        switch action {
        case .requestAccess: Task { await passkeys.requestAccess() }
        case .openPrivacySettings: NSWorkspace.shared.open(PasskeyAccessModel.privacySettingsURL)
        }
    }
}

/// Every profile, the spaces using each, and renaming and deleting them.
private struct ProfileSettings: View {
    let sidebar: SidebarStore
    let onDelete: (ProfileID) -> Void

    var body: some View {
        Form {
            Section("Profiles") {
                ForEach(sidebar.document.profiles) { profile in
                    row(profile)
                }
            }
            Text("Each profile keeps its own cookies, logins, site data and cache, so spaces with different profiles can be signed in to different accounts. Choose a space's profile from its menu in the space bar. Favourites use the profile of the space you're in. History and archived tabs are shared.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func row(_ profile: Profile) -> some View {
        let spaces = sidebar.document.spaces(using: profile.id)
        return HStack {
            VStack(alignment: .leading) {
                Text(profile.name)
                Text(describe(spaces)).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Rename") { rename(profile) }
            if !profile.isDefault {
                Button("Delete") { confirmDelete(profile, spaceCount: spaces.count) }
            }
        }
    }

    private func describe(_ spaces: [Space]) -> String {
        guard !spaces.isEmpty else { return "No spaces use it" }
        let names = spaces.map { $0.title ?? "Untitled space" }
        return "Used by " + ListFormatter.localizedString(byJoining: names)
    }

    private func rename(_ profile: Profile) {
        let alert = NSAlert()
        alert.messageText = "Rename Profile"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: profile.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        sidebar.renameProfile(profile.id, to: field.stringValue)
    }

    private func confirmDelete(_ profile: Profile, spaceCount: Int) {
        let alert = NSAlert()
        alert.messageText = "Delete the profile \(profile.name)?"
        let moving = switch spaceCount {
        case 0: ""
        case 1: " Its space moves to Default."
        default: " Its \(spaceCount) spaces move to Default."
        }
        alert.informativeText = "Sela deletes its cookies, logins, site data and cache, which signs you out of every site in it.\(moving) This can't be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        onDelete(profile.id)
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
