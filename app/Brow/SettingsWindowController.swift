import AppKit
import Browsing
import ContentBlocking
import History
import SwiftUI

/// Brow > Settings… (Cmd+,): General, Ad Blocking, Permissions and Import.
@MainActor
final class SettingsWindowController: NSWindowController {
    init(contentBlocker: ContentBlocker?, history: HistoryStore?, onSettingsChanged: @escaping () -> Void) {
        let view = SettingsView(contentBlocker: contentBlocker, history: history, onSettingsChanged: onSettingsChanged)
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
    let onSettingsChanged: () -> Void

    var body: some View {
        TabView {
            GeneralSettings(onSettingsChanged: onSettingsChanged).tabItem { Label("General", systemImage: "gearshape") }
            if let contentBlocker {
                AdBlockingSettings(blocker: contentBlocker).tabItem { Label("Ad Blocking", systemImage: "shield") }
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
                Text(isDefault ? "Brow is your default browser" : "Brow isn't your default browser")
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

    var body: some View {
        Form {
            Section("From Arc") {
                HStack {
                    Text("Your browsing history from the last 90 days")
                    Spacer()
                    Button("Import History") { HistoryImport.runAndReport(into: history, window: NSApp.keyWindow) }
                }
                Text("Your Arc sidebar is imported the first time Brow opens. Importing again would replace your Brow sidebar, so it isn't offered here.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
