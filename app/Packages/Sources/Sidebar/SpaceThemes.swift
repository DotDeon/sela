import Foundation
import SidebarModel

/// Colours for spaces that don't have their own: blue, purple, pink, red, orange, yellow, green, grey.
public let defaultSpaceColors: [RGBAColor] = [
    RGBAColor(red: 0.36, green: 0.55, blue: 0.93, alpha: 1),
    RGBAColor(red: 0.60, green: 0.45, blue: 0.90, alpha: 1),
    RGBAColor(red: 0.93, green: 0.45, blue: 0.66, alpha: 1),
    RGBAColor(red: 0.90, green: 0.38, blue: 0.35, alpha: 1),
    RGBAColor(red: 0.96, green: 0.60, blue: 0.30, alpha: 1),
    RGBAColor(red: 0.93, green: 0.78, blue: 0.30, alpha: 1),
    RGBAColor(red: 0.40, green: 0.75, blue: 0.45, alpha: 1),
    RGBAColor(red: 0.55, green: 0.57, blue: 0.60, alpha: 1),
]

/// The space's own colour, or a default picked by its position.
public func themeColor(for space: Space, at index: Int) -> RGBAColor {
    space.theme?.primary ?? defaultSpaceColors[index % defaultSpaceColors.count]
}
