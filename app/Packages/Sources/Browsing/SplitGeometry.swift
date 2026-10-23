import CoreGraphics
import SidebarModel

/// Where each pane of a split goes inside `bounds`, in a flipped coordinate space (y grows downwards).
/// Edges land on whole points, and the last pane takes any remainder so the panes always fill `bounds`.
public func paneFrames(in bounds: CGRect, orientation: SplitOrientation, fractions: [Double], gap: CGFloat) -> [CGRect] {
    guard !fractions.isEmpty else { return [] }
    let length = orientation == .horizontal ? bounds.width : bounds.height
    let available = max(length - gap * CGFloat(fractions.count - 1), 0)
    var edges: [CGFloat] = [0]
    var total = 0.0
    for fraction in fractions.dropLast() {
        total += fraction
        edges.append((available * CGFloat(total)).rounded())
    }
    edges.append(available)

    return fractions.indices.map { index in
        let start = edges[index] + gap * CGFloat(index)
        let size = edges[index + 1] - edges[index]
        switch orientation {
        case .horizontal: return CGRect(x: bounds.minX + start, y: bounds.minY, width: size, height: bounds.height)
        case .vertical: return CGRect(x: bounds.minX, y: bounds.minY + start, width: bounds.width, height: size)
        }
    }
}

/// The fractions after dragging the divider after pane `divider` so its centre sits at `position` along the split.
/// Only the two panes beside it change, and neither gets smaller than `minimum` points.
public func fractions(afterDragging divider: Int, to position: CGFloat, in bounds: CGRect, orientation: SplitOrientation,
                      fractions: [Double], gap: CGFloat, minimum: CGFloat) -> [Double] {
    guard fractions.indices.contains(divider + 1) else { return fractions }
    let frames = paneFrames(in: bounds, orientation: orientation, fractions: fractions, gap: gap)
    let available = Double(max((orientation == .horizontal ? bounds.width : bounds.height) - gap * CGFloat(fractions.count - 1), 1))
    let origin = orientation == .horizontal ? bounds.minX : bounds.minY
    let start = orientation == .horizontal ? frames[divider].minX : frames[divider].minY
    let pair = fractions[divider] + fractions[divider + 1]

    let pairLength = pair * available
    let wanted = Double(position - origin) - Double(gap) / 2 - Double(start - origin)
    let lowest = min(Double(minimum), pairLength / 2)
    let first = min(max(wanted, lowest), pairLength - lowest)

    var result = fractions
    result[divider] = first / available
    result[divider + 1] = pair - result[divider]
    return result
}
