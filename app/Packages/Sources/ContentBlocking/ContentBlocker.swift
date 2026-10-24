import BrowserEngine
import Foundation
import Observation

/// Sela's ad and tracker blocking: the settings, the downloaded lists, and the rules the engine applies.
/// Blocking is on by default and can be turned off everywhere or for one site at a time.
@MainActor
@Observable
public final class ContentBlocker {
    static let enabledKey = "BlockAdsAndTrackers"
    static let offSitesKey = "AdBlockingOffSites"

    public private(set) var isEnabled: Bool
    /// Sites, as `contentBlockingSite(for:)` names them, where blocking is off.
    public private(set) var offSites: Set<String>

    @ObservationIgnored private var engine: (any ContentBlockingEngine)?
    @ObservationIgnored private let store: FilterListStore
    @ObservationIgnored private let workFolder: URL
    @ObservationIgnored private let lists: [FilterList]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var lookup: PageScriptLookup?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    public init(engine: (any ContentBlockingEngine)?, store: FilterListStore, workFolder: URL, lists: [FilterList] = FilterList.defaults, defaults: UserDefaults = .standard) {
        self.engine = engine
        self.store = store
        self.workFolder = workFolder
        self.lists = lists
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        offSites = Set(defaults.stringArray(forKey: Self.offSitesKey) ?? [])
    }

    // MARK: Settings

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    /// False when blocking is off everywhere or for the URL's site. True for addresses with no site.
    public func isBlocking(on url: URL) -> Bool {
        guard isEnabled else { return false }
        guard let site = contentBlockingSite(for: url) else { return true }
        return !offSites.contains(site)
    }

    /// Turns blocking on or off for every page on the URL's site.
    public func setBlocking(_ on: Bool, forSiteOf url: URL) {
        guard let site = contentBlockingSite(for: url) else { return }
        setBlocking(on, forSite: site)
    }

    /// Turns blocking on or off for a site by the name `contentBlockingSite(for:)` gives it, as Settings lists them.
    public func setBlocking(_ on: Bool, forSite site: String) {
        if on { offSites.remove(site) } else { offSites.insert(site) }
        defaults.set(offSites.sorted(), forKey: Self.offSitesKey)
    }

    // MARK: Lists and rules

    /// True while any list has never downloaded, for example after a first launch with no network.
    /// The app retries sooner while this is true.
    public var isMissingLists: Bool {
        lists.contains { store.text(for: $0) == nil }
    }

    /// Connects to the engine, installs the lists already on disk, then downloads any that are missing or old.
    public func start() async {
        engine?.isContentBlockingEnabled = { [weak self] url in self?.isBlocking(on: url) ?? true }
        engine?.pageScripts = { [weak self] page, top in self?.pageScripts(page: page, top: top) }
        await rebuild()
        await refreshIfNeeded()
    }

    /// Downloads lists that are a day old or missing, and installs new rules when any changed.
    /// Calls that overlap share one run.
    public func refreshIfNeeded() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            if await store.refresh(lists) {
                await rebuild()
            }
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// Converts the saved lists off the main actor, then installs them and rebuilds the page script lookup.
    private func rebuild() async {
        let texts = lists.compactMap { list in store.text(for: list).map { (id: list.id, text: $0) } }
        guard !texts.isEmpty else { return }
        let compiled = await Task.detached(priority: .utility) { compileFilters(texts) }.value
        try? await engine?.installContentRules(compiled.ruleSets)
        lookup = try? PageScriptLookup(advancedRules: compiled.advancedRules, folder: workFolder.appending(path: "advanced"))
    }

    private func pageScripts(page: URL, top: URL?) -> PageScripts? {
        guard isBlocking(on: top ?? page) else { return nil }
        return lookup?.scripts(page: page, top: top)
    }
}
