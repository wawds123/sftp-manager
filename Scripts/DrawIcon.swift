// Draws the app icon: a rounded blue tile with two opposing transfer arrows.
// Run via Scripts/make_icon.sh — no Xcode or asset catalog needed.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

guard let context = CGContext(
    data: nil,
    width: side,
    height: side,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

let inset: CGFloat = 60
let tile = CGRect(x: inset, y: inset, width: CGFloat(side) - inset * 2, height: CGFloat(side) - inset * 2)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 200, cornerHeight: 200, transform: nil)

context.saveGState()
context.addPath(tilePath)
context.clip()
let colorSpace = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(colorSpace: colorSpace, components: [0.16, 0.47, 0.96, 1])!,
        CGColor(colorSpace: colorSpace, components: [0.05, 0.24, 0.66, 1])!,
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: tile.minX, y: tile.maxY),
    end: CGPoint(x: tile.maxX, y: tile.minY),
    options: []
)
context.restoreGState()

/// One horizontal arrow: a shaft plus a solid triangular head.
func arrow(y: CGFloat, pointingRight: Bool, length: CGFloat, thickness: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let centerX = CGFloat(side) / 2
    let headLength = thickness * 2.1
    let x0 = centerX - length / 2
    let x1 = centerX + length / 2
    let shaft = CGRect(
        x: pointingRight ? x0 : x0 + headLength,
        y: y - thickness / 2,
        width: length - headLength,
        height: thickness
    )
    path.addRoundedRect(in: shaft, cornerWidth: thickness / 2, cornerHeight: thickness / 2)

    let tipX = pointingRight ? x1 : x0
    let baseX = pointingRight ? x1 - headLength : x0 + headLength
    path.move(to: CGPoint(x: tipX, y: y))
    path.addLine(to: CGPoint(x: baseX, y: y + thickness * 1.5))
    path.addLine(to: CGPoint(x: baseX, y: y - thickness * 1.5))
    path.closeSubpath()
    return path
}

context.setFillColor(CGColor(colorSpace: colorSpace, components: [1, 1, 1, 0.96])!)
context.addPath(arrow(y: CGFloat(side) * 0.60, pointingRight: true, length: 520, thickness: 74))
context.fillPath()
context.setFillColor(CGColor(colorSpace: colorSpace, components: [0.78, 0.89, 1, 0.95])!)
context.addPath(arrow(y: CGFloat(side) * 0.40, pointingRight: false, length: 520, thickness: 74))
context.fillPath()

guard let image = context.makeImage() else { exit(1) }
let url = URL(fileURLWithPath: output)
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
