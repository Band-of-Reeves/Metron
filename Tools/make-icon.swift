// Renders Metron's app icon.
//
// The icon is the menu bar glyph at Dock scale on purpose: a ring filled to a
// fraction, on the app's own dark surface. The thing in your menu bar and the
// thing in your Dock should read as one object.
//
//   swift Tools/make-icon.swift <#RRGGBB accent> <out-dir>
//
// Writes every size macOS wants plus the .icns. Run from the repo root.

import AppKit
import Foundation

let args = CommandLine.arguments
let accentHex = args.count > 1 ? args[1] : "D97757"
let outDir = args.count > 2 ? args[2] : "dist/icon"

func color(_ hex: String, alpha: CGFloat = 1) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
    return NSColor(red: CGFloat((v >> 16) & 0xff) / 255,
                   green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: alpha)
}

/// The fraction the ring is drawn at. Not full, not nearly empty — a readout
/// caught mid-reading, which is what the app is.
let fraction = 0.72

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!
    ctx.imageInterpolation = .high

    // macOS icon grid: the rounded rect occupies 824 of a 1024 canvas, corner
    // radius 185.4. Everything below is expressed against that so the icon
    // scales without drifting.
    let u = size / 1024
    let plateSide = 824 * u
    let plate = NSRect(x: (size - plateSide) / 2, y: (size - plateSide) / 2,
                       width: plateSide, height: plateSide)
    let shape = NSBezierPath(roundedRect: plate, xRadius: 185.4 * u, yRadius: 185.4 * u)

    // Dark zinc, lifted very slightly at the top so the plate reads as a
    // surface rather than a hole.
    // How far into "small icon" territory we are: 0 at 64pt and above, 1 at 16pt.
    let small = max(0, min(1, (64 - size) / 48))   // 0 at 64pt, 1 at 16pt

    // Lift the plate a little as it shrinks too — at 16pt a near-black square
    // on a dark Dock or sidebar has no edge at all.
    NSGradient(colors: [color("232325").blended(withFraction: 0.10 * small, of: .white)!,
                        color("101011").blended(withFraction: 0.10 * small, of: .white)!])?
        .draw(in: shape, angle: -90)

    // A hairline inner edge. Without it the plate dissolves into a dark Dock.
    shape.lineWidth = 2 * u
    color("FFFFFF", alpha: 0.07).setStroke()
    shape.stroke()

    // The ring, centred, at the same proportions as the menu bar glyph — but
    // opened up as the canvas shrinks. Scaled linearly, the stroke lands near
    // one pixel at 16pt and the icon reads as an empty plate in a Finder list.
    // Below 64pt the ring grows into the plate and thickens, which is what
    // every well-behaved macOS icon does at these sizes.
    let ringDiameter = (440 + 190 * small) * u
    let lineWidth = (62 + 78 * small) * u
    let ring = NSRect(x: (size - ringDiameter) / 2, y: (size - ringDiameter) / 2,
                      width: ringDiameter, height: ringDiameter)

    let track = NSBezierPath(ovalIn: ring)
    track.lineWidth = lineWidth
    color("FFFFFF", alpha: 0.10).setStroke()
    track.stroke()

    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x: ring.midX, y: ring.midY),
                  radius: ringDiameter / 2,
                  startAngle: 90,
                  endAngle: 90 - 360 * fraction,
                  clockwise: true)
    arc.lineWidth = lineWidth
    arc.lineCapStyle = .round
    color(accentHex).setStroke()
    arc.stroke()

    image.unlockFocus()
    return image
}

func png(_ image: NSImage, _ side: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(side)).draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = "\(outDir)/Metron.iconset"
try? fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

// The set macOS actually asks for. 16 and 32 are drawn, not downsampled, so
// the ring stays crisp at menu-bar-adjacent sizes.
let wanted: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
for (side, name) in wanted {
    try! png(drawIcon(size: CGFloat(side)), side).write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}
try! png(drawIcon(size: 1024), 1024).write(to: URL(fileURLWithPath: "\(outDir)/preview.png"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", "\(outDir)/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print("wrote \(outDir)/AppIcon.icns and preview.png (accent #\(accentHex))")
