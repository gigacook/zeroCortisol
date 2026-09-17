// Generates the zeroCortisol icons with CoreGraphics.
//
//   swift scripts/make_icon.swift <output-dir>
//
// Writes into <output-dir>:
//   AppIcon.icns                          (via iconutil, from a temporary .iconset)
//   menubar_closed.png / menubar_closed@2x.png   (template: closed eye over pyramid, 18pt)
//   menubar_open.png   / menubar_open@2x.png     (template: open eye over pyramid, 18pt)

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Bitmap helpers

func makeContext(pixels: Int) -> CGContext {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    return ctx
}

func writePNG(_ ctx: CGContext, to url: URL) {
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("cannot create PNG at \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(url.path)") }
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// Almond (vesica) eye outline centred at `c`, width `w`, height `h`.
func almondPath(center c: CGPoint, width w: CGFloat, height h: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let left = CGPoint(x: c.x - w / 2, y: c.y)
    let right = CGPoint(x: c.x + w / 2, y: c.y)
    p.move(to: left)
    p.addQuadCurve(to: right, control: CGPoint(x: c.x, y: c.y + h))
    p.addQuadCurve(to: left, control: CGPoint(x: c.x, y: c.y - h))
    p.closeSubpath()
    return p
}

// MARK: - App icon (1024 design space)

func drawAppIcon(_ ctx: CGContext, pixels: Int) {
    let s = CGFloat(pixels) / 1024
    ctx.saveGState()
    ctx.scaleBy(x: s, y: s)

    // Rounded-square plate with the standard macOS margin.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(platePath)
    ctx.setFillColor(color(0x070B18))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    let sea = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
        color(0x1B2B52), color(0x0B1330), color(0x05070F),
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawRadialGradient(sea, startCenter: CGPoint(x: 512, y: 640), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 560), endRadius: 620, options: [.drawsAfterEndLocation])

    // Faint rays behind the eye.
    let eyeCenter = CGPoint(x: 512, y: 560)
    ctx.saveGState()
    ctx.setStrokeColor(color(0xF3D38B, 0.10))
    ctx.setLineWidth(6)
    for i in 0..<24 {
        let a = CGFloat(i) / 24 * 2 * .pi
        ctx.move(to: CGPoint(x: eyeCenter.x + cos(a) * 170, y: eyeCenter.y + sin(a) * 170))
        ctx.addLine(to: CGPoint(x: eyeCenter.x + cos(a) * 520, y: eyeCenter.y + sin(a) * 520))
    }
    ctx.strokePath()
    ctx.restoreGState()

    // Scattered stars.
    var seed: UInt32 = 7
    func rnd() -> CGFloat { seed = seed &* 1_664_525 &+ 1_013_904_223; return CGFloat(seed % 10_000) / 10_000 }
    for _ in 0..<40 {
        let x = 120 + rnd() * 784, y = 520 + rnd() * 380, r = 1.5 + rnd() * 3.5
        ctx.setFillColor(color(0xDCE6FF, 0.25 + rnd() * 0.5))
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    // Pyramid.
    let apex = CGPoint(x: 512, y: 780), baseL = CGPoint(x: 210, y: 250), baseR = CGPoint(x: 814, y: 250)
    let pyramid = CGMutablePath()
    pyramid.move(to: apex); pyramid.addLine(to: baseR); pyramid.addLine(to: baseL); pyramid.closeSubpath()
    ctx.saveGState()
    ctx.addPath(pyramid)
    ctx.clip()
    let gold = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
        color(0xF6DC9A), color(0xC99A45), color(0x7A5621),
    ] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(gold, start: CGPoint(x: 380, y: 780), end: CGPoint(x: 700, y: 250),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // Shaded right face.
    let face = CGMutablePath()
    face.move(to: apex); face.addLine(to: baseR); face.addLine(to: CGPoint(x: 600, y: 250)); face.closeSubpath()
    ctx.addPath(face)
    ctx.setFillColor(color(0x000000, 0.18))
    ctx.fillPath()
    // Courses of stone.
    ctx.setStrokeColor(color(0x3B2A10, 0.28))
    ctx.setLineWidth(5)
    var y: CGFloat = 310
    while y < 470 {
        ctx.move(to: CGPoint(x: 150, y: y)); ctx.addLine(to: CGPoint(x: 880, y: y))
        y += 58
    }
    ctx.strokePath()
    ctx.restoreGState()

    ctx.addPath(pyramid)
    ctx.setStrokeColor(color(0xFBE7B5, 0.9))
    ctx.setLineWidth(10)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    // Eye overlapping the upper pyramid: dark halo, white almond, iris, pupil, glint.
    let eyeW: CGFloat = 470, eyeH: CGFloat = 250
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: color(0xF3D38B, 0.55))
    ctx.addPath(almondPath(center: eyeCenter, width: eyeW + 40, height: eyeH + 30))
    ctx.setFillColor(color(0x070B18))
    ctx.fillPath()
    ctx.restoreGState()

    let eye = almondPath(center: eyeCenter, width: eyeW, height: eyeH)
    ctx.saveGState()
    ctx.addPath(eye)
    ctx.clip()
    let white = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
        color(0xFFFFFF), color(0xDCE3F0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(white, startCenter: eyeCenter, startRadius: 0, endCenter: eyeCenter, endRadius: 240, options: [.drawsAfterEndLocation])
    let irisR: CGFloat = 92
    let iris = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
        color(0x6FB6E8), color(0x245E9E), color(0x0E2748),
    ] as CFArray, locations: [0, 0.6, 1])!
    ctx.addEllipse(in: CGRect(x: eyeCenter.x - irisR, y: eyeCenter.y - irisR, width: irisR * 2, height: irisR * 2))
    ctx.clip()
    ctx.drawRadialGradient(iris, startCenter: eyeCenter, startRadius: 0, endCenter: eyeCenter, endRadius: irisR, options: [])
    ctx.restoreGState()

    ctx.setFillColor(color(0x03060C))
    ctx.fillEllipse(in: CGRect(x: eyeCenter.x - 40, y: eyeCenter.y - 40, width: 80, height: 80))
    ctx.setFillColor(color(0xFFFFFF, 0.9))
    ctx.fillEllipse(in: CGRect(x: eyeCenter.x + 18, y: eyeCenter.y + 22, width: 30, height: 30))

    ctx.addPath(eye)
    ctx.setStrokeColor(color(0x0A0F1E))
    ctx.setLineWidth(16)
    ctx.strokePath()

    ctx.restoreGState()  // plate clip
    ctx.restoreGState()  // scale
}

// MARK: - Menu bar template images (18pt design space, black on transparent)

func drawMenuBar(_ ctx: CGContext, scale: CGFloat, open: Bool) {
    ctx.saveGState()
    ctx.scaleBy(x: scale, y: scale)
    let black = color(0x000000)
    ctx.setStrokeColor(black)
    ctx.setFillColor(black)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)

    // Pyramid outline.
    let pyramid = CGMutablePath()
    pyramid.move(to: CGPoint(x: 9, y: 16.6))
    pyramid.addLine(to: CGPoint(x: 16.8, y: 2.2))
    pyramid.addLine(to: CGPoint(x: 1.2, y: 2.2))
    pyramid.closeSubpath()
    ctx.addPath(pyramid)
    ctx.setLineWidth(1.4)
    ctx.strokePath()

    let c = CGPoint(x: 9, y: 8.4)
    if open {
        let eye = almondPath(center: c, width: 11.4, height: 6.4)
        // Knock the pyramid lines out behind the eye so it reads cleanly.
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.addPath(almondPath(center: c, width: 13.6, height: 8.2))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(eye)
        ctx.setLineWidth(1.3)
        ctx.strokePath()
        ctx.fillEllipse(in: CGRect(x: c.x - 1.9, y: c.y - 1.9, width: 3.8, height: 3.8))
    } else {
        // Closed lid: a downward arc with three short lashes.
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.addPath(almondPath(center: c, width: 13.6, height: 8.2))
        ctx.fillPath()
        ctx.restoreGState()
        let lid = CGMutablePath()
        lid.move(to: CGPoint(x: c.x - 5.6, y: c.y))
        lid.addQuadCurve(to: CGPoint(x: c.x + 5.6, y: c.y), control: CGPoint(x: c.x, y: c.y - 4.2))
        ctx.addPath(lid)
        ctx.setLineWidth(1.3)
        ctx.strokePath()
        for (dx, len) in [(-3.2, 1.6), (0.0, 1.8), (3.2, 1.6)] {
            let t = CGFloat(0.5 + dx / 11.2)
            // Point on the quadratic lid at parameter t.
            let x = (1 - t) * (1 - t) * (c.x - 5.6) + 2 * (1 - t) * t * c.x + t * t * (c.x + 5.6)
            let y = (1 - t) * (1 - t) * c.y + 2 * (1 - t) * t * (c.y - 4.2) + t * t * c.y
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + CGFloat(dx) * 0.18, y: y - CGFloat(len)))
        }
        ctx.setLineWidth(1.1)
        ctx.strokePath()
    }
    ctx.restoreGState()
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: swift scripts/make_icon.swift <output-dir>\n".data(using: .utf8)!)
    exit(2)
}
let fm = FileManager.default
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset", isDirectory: true)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: iconset) }

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let ctx = makeContext(pixels: px)
        drawAppIcon(ctx, pixels: px)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        writePNG(ctx, to: iconset.appendingPathComponent(name))
    }
}

let icns = outDir.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}

for (name, open) in [("menubar_closed", false), ("menubar_open", true)] {
    for scale in [1, 2] {
        let ctx = makeContext(pixels: 18 * scale)
        drawMenuBar(ctx, scale: CGFloat(scale), open: open)
        writePNG(ctx, to: outDir.appendingPathComponent(scale == 1 ? "\(name).png" : "\(name)@2x.png"))
    }
}

// A 1024px preview is handy for README / inspection; not needed by the app.
let preview = makeContext(pixels: 1024)
drawAppIcon(preview, pixels: 1024)
writePNG(preview, to: outDir.appendingPathComponent("AppIcon-1024.png"))

print("wrote \(icns.path) and menu bar templates to \(outDir.path)")
