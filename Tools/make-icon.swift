import AppKit
import CoreGraphics

// Renders the app icon: the notch at the top of a dark court, the ball falling
// out of it. Run: swift Tools/make-icon.swift <output-dir>

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func draw(into ctx: CGContext) {
    let square = CGRect(x: 100, y: 100, width: 824, height: 824)
    let radius: CGFloat = 185

    // Court background: a deep navy vertical gradient.
    let path = CGPath(roundedRect: square, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path); ctx.clip()
    let colors = [
        CGColor(red: 0.055, green: 0.082, blue: 0.133, alpha: 1),
        CGColor(red: 0.106, green: 0.145, blue: 0.212, alpha: 1)
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
        start: CGPoint(x: 512, y: square.minY),
        end: CGPoint(x: 512, y: square.maxY), options: [])

    // The notch, hanging from the top edge: near-black, bright lower lip.
    let notch = CGRect(x: 512 - 160, y: square.maxY - 92, width: 320, height: 140)
    let notchPath = CGPath(roundedRect: notch, cornerWidth: 34, cornerHeight: 34, transform: nil)
    ctx.setFillColor(CGColor(red: 0.02, green: 0.027, blue: 0.043, alpha: 1))
    ctx.addPath(notchPath); ctx.fillPath()
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.32))
    ctx.setLineWidth(5)
    ctx.addPath(notchPath); ctx.strokePath()

    // Fall streaks between the notch and the ball.
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.28))
    ctx.setLineCap(.round)
    ctx.setLineWidth(14)
    for (dx, top, len): (CGFloat, CGFloat, CGFloat) in [(-70, 812, 74), (66, 786, 56)] {
        ctx.move(to: CGPoint(x: 512 + dx, y: top))
        ctx.addLine(to: CGPoint(x: 512 + dx, y: top - len))
        ctx.strokePath()
    }

    // The ball.
    let center = CGPoint(x: 512, y: 400)
    let r: CGFloat = 244
    let ball = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
    ctx.setFillColor(CGColor(red: 0.945, green: 0.42, blue: 0.11, alpha: 1))
    ctx.fillEllipse(in: ball)
    // Soft top-light.
    ctx.saveGState()
    ctx.addEllipse(in: ball); ctx.clip()
    let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        CGColor(red: 1, green: 0.62, blue: 0.25, alpha: 0.85),
        CGColor(red: 0.945, green: 0.42, blue: 0.11, alpha: 0)
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(sheen,
        startCenter: CGPoint(x: 512 - 70, y: 500), startRadius: 0,
        endCenter: center, endRadius: r * 1.15, options: [])
    ctx.restoreGState()

    // Seams, clipped to the ball.
    ctx.saveGState()
    ctx.addEllipse(in: ball); ctx.clip()
    ctx.setStrokeColor(CGColor(red: 0.28, green: 0.13, blue: 0.045, alpha: 1))
    ctx.setLineWidth(17)
    ctx.strokeEllipse(in: ball.insetBy(dx: 8, dy: 8))
    ctx.move(to: CGPoint(x: center.x, y: ball.minY))
    ctx.addLine(to: CGPoint(x: center.x, y: ball.maxY)); ctx.strokePath()
    ctx.move(to: CGPoint(x: ball.minX, y: center.y))
    ctx.addLine(to: CGPoint(x: ball.maxX, y: center.y)); ctx.strokePath()
    for side: CGFloat in [-1, 1] {
        let arcCenter = CGPoint(x: center.x + (side * r * 1.55), y: center.y)
        ctx.addArc(center: arcCenter, radius: r * 0.95,
                   startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ctx.strokePath()
    }
    ctx.restoreGState()
}

let space = CGColorSpaceCreateDeviceRGB()
let master = CGContext(data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
draw(into: master)
let masterImage = master.makeImage()!

for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    let ctx = CGContext(data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(masterImage, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let image = ctx.makeImage()!
    let url = URL(fileURLWithPath: "\(out)/icon_\(pixels).png") as CFURL
    let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("icon_\(pixels).png")
}
