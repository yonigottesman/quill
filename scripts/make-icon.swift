// Renders a 1024×1024 app-icon PNG: the menu-bar `pencil.line` SF Symbol in
// white on a rounded indigo gradient. Usage: swift make-icon.swift <out.png>
import AppKit

let outPath = CommandLine.arguments[1]
let S = 1024
let size = CGFloat(S)

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

// Rounded squircle-ish background with an indigo gradient.
let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                      xRadius: size * 0.2237, yRadius: size * 0.2237)
NSGradient(colors: [
    NSColor(srgbRed: 0.36, green: 0.41, blue: 0.96, alpha: 1),
    NSColor(srgbRed: 0.17, green: 0.21, blue: 0.58, alpha: 1),
])!.draw(in: bg, angle: -90)

// pencil.line symbol, white, centered at ~58% of the canvas.
let cfg = NSImage.SymbolConfiguration(pointSize: 600, weight: .regular)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
let sym = NSImage(systemSymbolName: "pencil.line", accessibilityDescription: nil)!
    .withSymbolConfiguration(cfg)!
let scale = (size * 0.58) / max(sym.size.width, sym.size.height)
let dw = sym.size.width * scale, dh = sym.size.height * scale
sym.draw(in: NSRect(x: (size - dw) / 2, y: (size - dh) / 2, width: dw, height: dh))

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
