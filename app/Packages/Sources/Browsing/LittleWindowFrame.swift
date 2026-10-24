import CoreGraphics
import Foundation

/// Where Little Sela windows go. The last one moved or resized sets the frame for the next, stored in `UserDefaults`.
public struct LittleWindowFrame {
    public static let key = "LittleWindowFrame"
    public static let defaultSize = CGSize(width: 900, height: 700)
    public static let minimumSize = CGSize(width: 480, height: 360)
    /// How far each window sits down and right of one already open in the same place.
    static let cascadeStep: CGFloat = 24

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The frame saved last, or nil before any window has been moved or resized.
    public var saved: CGRect? {
        get {
            guard let values = defaults.array(forKey: Self.key) as? [Double], values.count == 4 else { return nil }
            let rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            return rect.width > 0 && rect.height > 0 ? rect : nil
        }
        nonmutating set {
            guard let rect = newValue else {
                defaults.removeObject(forKey: Self.key)
                return
            }
            defaults.set([rect.minX, rect.minY, rect.width, rect.height].map(Double.init), forKey: Self.key)
        }
    }

    /// The frame for a new window on a screen whose usable area is `visible`: the saved frame, or the default size
    /// in the middle. Always fits on screen. Steps down and right while a window in `occupied` already sits there.
    /// Uses AppKit's screen coordinates, where y grows upwards.
    public func frameForNewWindow(visible: CGRect, occupied: [CGRect]) -> CGRect {
        let wanted = saved.map(\.size) ?? Self.defaultSize
        let size = CGSize(
            width: min(max(wanted.width, Self.minimumSize.width), visible.width),
            height: min(max(wanted.height, Self.minimumSize.height), visible.height)
        )
        var origin = saved?.origin ?? CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        origin = Self.clamp(origin, size: size, into: visible)

        var tries = 0
        while occupied.contains(where: { Self.sameTopLeft($0, CGRect(origin: origin, size: size)) }), tries < 20 {
            var next = CGPoint(x: origin.x + Self.cascadeStep, y: origin.y - Self.cascadeStep)
            // Off the bottom or right edge, start again at the top left.
            if next.x + size.width > visible.maxX || next.y < visible.minY {
                next = CGPoint(x: visible.minX, y: visible.maxY - size.height)
            }
            origin = next
            tries += 1
        }
        return CGRect(origin: origin, size: size)
    }

    private static func clamp(_ origin: CGPoint, size: CGSize, into visible: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, visible.minX), visible.maxX - size.width),
            y: min(max(origin.y, visible.minY), visible.maxY - size.height)
        )
    }

    /// True when the top left corners are within a couple of points. AppKit's origin is the bottom left corner.
    private static func sameTopLeft(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.maxY - b.maxY) < 2
    }
}
