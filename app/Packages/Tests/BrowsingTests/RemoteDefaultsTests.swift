import Foundation
import Testing
import Browsing
import RemoteSettings

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "sela-remote-\(UUID().uuidString)")!
}

private func remote(engines: [RemoteSearchEngine?] = [], defaults: RemoteDefaults = RemoteDefaults()) -> RemoteSettings {
    RemoteSettings(searchEngines: engines.compactMap { $0 }, defaults: defaults)
}

@Test func remoteDefaultsApplyUntilYouChoose() {
    let settings = remote(defaults: RemoteDefaults(searchEngine: "duckduckgo", tabSleepMinutes: 60, autoPictureInPicture: false))
    let defaults = freshDefaults()
    #expect(SearchEngineSettings(defaults: defaults, remote: settings).engine == .duckDuckGo)
    #expect(TabSleepSettings(defaults: defaults, remote: settings).minutes == 60)
    #expect(!PictureInPictureSettings(defaults: defaults, remote: settings).isEnabled)
}

@Test func yourChoiceWinsOverRemoteDefaults() {
    let defaults = freshDefaults()
    SearchEngineSettings(defaults: defaults).engine = .kagi
    TabSleepSettings(defaults: defaults).minutes = 5
    PictureInPictureSettings(defaults: defaults).isEnabled = false

    let settings = remote(defaults: RemoteDefaults(searchEngine: "duckduckgo", tabSleepMinutes: 60, autoPictureInPicture: true))
    #expect(SearchEngineSettings(defaults: defaults, remote: settings).engine == .kagi)
    #expect(TabSleepSettings(defaults: defaults, remote: settings).minutes == 5)
    #expect(!PictureInPictureSettings(defaults: defaults, remote: settings).isEnabled)
}

@Test func choosingTheValueInUseDoesNotPinIt() {
    let defaults = freshDefaults()
    TabSleepSettings(defaults: defaults).minutes = 15
    SearchEngineSettings(defaults: defaults).engine = .google
    PictureInPictureSettings(defaults: defaults).isEnabled = true

    let settings = remote(defaults: RemoteDefaults(searchEngine: "bing", tabSleepMinutes: 60, autoPictureInPicture: false))
    #expect(TabSleepSettings(defaults: defaults, remote: settings).minutes == 60)
    #expect(SearchEngineSettings(defaults: defaults, remote: settings).engine == .bing)
    #expect(!PictureInPictureSettings(defaults: defaults, remote: settings).isEnabled)
}

@Test func remoteDefaultsThatAreNotChoicesAreIgnored() {
    let settings = remote(defaults: RemoteDefaults(searchEngine: "altavista", tabSleepMinutes: 7))
    let defaults = freshDefaults()
    #expect(TabSleepSettings(defaults: defaults, remote: settings).minutes == 15)
    #expect(SearchEngineSettings(defaults: defaults, remote: settings).engine == .google)
}

@Test func remoteEnginesChangeBuiltInOnesAndAddNewOnes() throws {
    let settings = remote(engines: [
        RemoteSearchEngine(id: "google", name: "Google", template: "https://www.google.com/search?udm=14&q=%s"),
        RemoteSearchEngine(id: "mojeek", name: "Mojeek", template: "https://www.mojeek.com/search?q=%s"),
    ])
    let engines = SearchEngine.available(remote: settings)
    #expect(engines.map(\.id) == SearchEngine.builtIn.map(\.id) + ["mojeek"])
    let google = try #require(engines.first)
    #expect(google.searchURL(for: "swift")?.absoluteString == "https://www.google.com/search?udm=14&q=swift")
}

@Test func yourChosenEngineStaysChosenWhenItsTemplateChanges() {
    let defaults = freshDefaults()
    SearchEngineSettings(defaults: defaults).engine = .ecosia
    let settings = remote(engines: [RemoteSearchEngine(id: "ecosia", name: "Ecosia", template: "https://www.ecosia.org/search?method=index&q=%s")])
    let engine = SearchEngineSettings(defaults: defaults, remote: settings).engine
    #expect(engine.id == "ecosia")
    #expect(engine.template == "https://www.ecosia.org/search?method=index&q=%s")
    // Once the change goes away, the built-in template is back.
    #expect(SearchEngineSettings(defaults: defaults, remote: .empty).engine == .ecosia)
}

@Test func anAddedEngineThatGoesAwayFallsBackAndComesBack() {
    let defaults = freshDefaults()
    let settings = remote(engines: [RemoteSearchEngine(id: "mojeek", name: "Mojeek", template: "https://www.mojeek.com/search?q=%s")])
    let mojeek = SearchEngineSettings(defaults: defaults, remote: settings).available.last!
    SearchEngineSettings(defaults: defaults, remote: settings).engine = mojeek
    #expect(SearchEngineSettings(defaults: defaults, remote: settings).engine == mojeek)

    #expect(SearchEngineSettings(defaults: defaults, remote: .empty).engine == .google)
    #expect(defaults.string(forKey: SearchEngineSettings.key) == "mojeek")
    #expect(SearchEngineSettings(defaults: defaults, remote: settings).engine == mojeek)
}
