import Foundation
@testable import CommandBar
import SidebarModel

let base = Date(timeIntervalSince1970: 1_800_000_000)

func tab(_ title: String, _ host: String? = nil, minutesAgo: Double = 0) -> TabCandidate {
    let host = host ?? title.lowercased().replacingOccurrences(of: " ", with: "-")
    return TabCandidate(id: ItemID(rawValue: "tab-\(host)"), title: title, url: URL(string: "https://\(host).example.com/"), lastActiveAt: base.addingTimeInterval(-minutesAgo * 60))
}

func command(_ title: String) -> CommandCandidate {
    CommandCandidate(id: title.lowercased(), title: title, keywords: [])
}

func archived(_ title: String) -> ArchivedCandidate {
    ArchivedCandidate(id: UUID(), title: title, url: URL(string: "https://\(title.lowercased().replacingOccurrences(of: " ", with: "-")).archive.example.com/"))
}

func history(_ title: String, url: String? = nil) -> HistoryCandidate {
    HistoryCandidate(url: URL(string: url ?? "https://\(title.lowercased().replacingOccurrences(of: " ", with: "-")).history.example.com/")!, title: title)
}
