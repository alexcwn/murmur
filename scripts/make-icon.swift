// Generates Resources/AppIcon.icns.
//
// Direction 02 "Lamp" from docs/icon.html: one record lamp seated in a dark
// bezel on a brushed aluminium plate. Drawn programmatically rather than
// exported from a design tool so the small sizes can be genuinely different
// artwork — at 16 and 32 the striation, the specular highlight and the softer
// bezel all disappear, because they turn to mush rather than detail.
//
//   swift scripts/make-icon.swift
import AppKit

let ROOT = FileManager.default.currentDirectoryPath
let CANVAS: CGFloat = 1024

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// Deck palette, from Sources/Murmur/Design/Tokens.swift
let plateLight = rgb(0xE6E2D9), plateMid = rgb(0xB6B2A9)
let plateEdge  = rgb(0x8E9296), plateDark = rgb(0x5E6266)
let bezelFill  = rgb(0x4A4E52), bezelRing = rgb(0x33363A)
let lampHot    = rgb(0xF2705F), lampBody  = rgb(0xD23F32), lampDeep = rgb(0x8E2018)

/// Apple's icon grid: the shape occupies 824 of 1024, leaving room for shadow.
let inset: CGFloat = 100
let plateSize: CGFloat = CANVAS - inset * 2
let plateRadius: CGFloat = 185

func squircle() -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: plateSize, height: plateSize),
                 xRadius: plateRadius, yRadius: plateRadius)
}

func draw(simplified: Bool, textured: Bool) {
    let plate = squircle()

    // Plate. Light from the upper left, falling off toward the lower right.
    let grad = NSGradient(colors: simplified ? [plateLight, plateEdge]
                                             : [plateLight, plateMid, plateEdge, plateDark],
                          atLocations: simplified ? [0, 1] : [0, 0.45, 0.72, 1],
                          colorSpace: .sRGB)!
    grad.draw(in: plate, angle: -45)

    // Brushed striation. Only where it reads as texture rather than noise.
    if textured {
        NSGraphicsContext.saveGraphicsState()
        plate.addClip()
        var x = inset
        while x < inset + plateSize {
            NSColor.white.withAlphaComponent(0.05).setFill()
            NSRect(x: x, y: inset, width: 2, height: plateSize).fill()
            NSColor.black.withAlphaComponent(0.035).setFill()
            NSRect(x: x + 2, y: inset, width: 2, height: plateSize).fill()
            x += 4
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    let c = NSPoint(x: CANVAS / 2, y: CANVAS / 2)

    // Bezel. Thickened when simplified so the lamp still reads as *seated*
    // rather than as a flat dot printed on a square.
    let bezelR: CGFloat = 300
    let ringW: CGFloat = simplified ? 40 : 26
    let bezel = NSBezierPath(ovalIn: NSRect(x: c.x - bezelR, y: c.y - bezelR,
                                            width: bezelR * 2, height: bezelR * 2))
    bezelFill.setFill()
    bezel.fill()
    bezelRing.setStroke()
    bezel.lineWidth = ringW
    bezel.stroke()

    // Lamp.
    let lampR: CGFloat = simplified ? 244 : 238
    let lamp = NSBezierPath(ovalIn: NSRect(x: c.x - lampR, y: c.y - lampR,
                                           width: lampR * 2, height: lampR * 2))
    NSGraphicsContext.saveGraphicsState()
    lamp.addClip()
    if simplified {
        lampBody.setFill()
        lamp.fill()
    } else {
        let bulb = NSGradient(colors: [lampHot, lampBody, lampDeep],
                              atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
        bulb.draw(fromCenter: NSPoint(x: c.x - 78, y: c.y + 86), radius: 0,
                  toCenter: c, radius: lampR * 1.08, options: [])
    }
    NSGraphicsContext.restoreGraphicsState()

    // Specular highlight — the one thing that says "glass bulb" and the first
    // thing that becomes a smudge, so it is large-size only.
    if !simplified {
        let hl = NSBezierPath(ovalIn: NSRect(x: -86, y: -58, width: 172, height: 116))
        let t = NSAffineTransform()
        t.translateX(by: c.x - 74, yBy: c.y + 88)
        t.rotate(byDegrees: 28)
        hl.transform(using: t as AffineTransform)
        NSColor.white.withAlphaComponent(0.26).setFill()
        hl.fill()
    }
}

func render(px: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("could not allocate \(px)px bitmap") }

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("no context") }
    NSGraphicsContext.current = ctx
    ctx.cgContext.setAllowsAntialiasing(true)
    ctx.imageInterpolation = .high
    let s = CGFloat(px) / CANVAS
    ctx.cgContext.scaleBy(x: s, y: s)

    draw(simplified: px <= 32, textured: px >= 128)

    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
    try data.write(to: url)
}

let iconset = URL(fileURLWithPath: ROOT).appendingPathComponent(".build/Murmur.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The ten entries iconutil expects.
let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in variants {
    try render(px: px, to: iconset.appendingPathComponent("\(name).png"))
    print("  \(px)px\t\(name).png\(px <= 32 ? "\t(simplified)" : "")")
}
print("iconset at \(iconset.path)")
