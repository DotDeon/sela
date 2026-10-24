import Foundation

/// A new GitHub issue for Sela, prefilled with a short template and the Mac it runs on.
/// Holds nothing personal: no pages, tab titles, user name or paths.
public struct ProblemReport: Equatable, Sendable {
    public static let newIssueURL = URL(string: "https://github.com/DotDeon/sela/issues/new")!

    public var appVersion: String
    public var appBuild: String
    public var macOSVersion: String
    /// Such as "Mac15,6".
    public var macModel: String
    /// "arm64" or "x86_64".
    public var chip: String

    public init(appVersion: String, appBuild: String, macOSVersion: String, macModel: String, chip: String) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.macOSVersion = macOSVersion
        self.macModel = macModel
        self.chip = chip
    }

    /// This copy of Sela and this Mac.
    public static func current(bundle: Bundle = .main) -> ProblemReport {
        ProblemReport(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            macModel: sysctlString("hw.model") ?? "unknown",
            chip: chipArchitecture()
        )
    }

    public var body: String {
        """
        ### What happened



        ### What you expected



        ### Steps to reproduce

        1.

        ### Your Mac

        - Sela: \(appVersion) (\(appBuild))
        - macOS: \(macOSVersion)
        - Mac: \(macModel)
        - Chip: \(chip)
        """
    }

    /// The new issue page with the body filled in. The title is left for the person reporting.
    public var issueURL: URL {
        URL(string: "\(Self.newIssueURL.absoluteString)?body=\(Self.encode(body))")!
    }

    /// Percent-encodes everything but letters, digits and `-._~`, so `&`, `=`, `+` and `#` can't end the value early.
    static func encode(_ value: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }

    /// The chip itself, so a copy running under Rosetta still reports Apple silicon.
    private static func chipArchitecture() -> String {
        var arm64: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &arm64, &size, nil, 0) == 0, arm64 == 1 { return "arm64" }
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}
