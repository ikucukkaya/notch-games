import CoreGraphics
import Foundation

/// One horizontal cord loop of the net. The net is a cone of revolution seen
/// from the side, so a loop needs only three degrees of freedom: how far it has
/// stretched, how far it has sagged, and how far its centre has swung sideways.
/// Everything the renderer draws is derived from these three numbers, which is
/// why the cords can never tangle.
struct NetRing {
    var radius: CGFloat
    var centerX: CGFloat
    var centerY: CGFloat

    var radiusVelocity: CGFloat = 0
    var centerXVelocity: CGFloat = 0
    var centerYVelocity: CGFloat = 0

    let restRadius: CGFloat
    let restCenterY: CGFloat
    let isPinned: Bool
}
