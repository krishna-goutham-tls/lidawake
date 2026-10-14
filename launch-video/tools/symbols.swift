// Renders the SF Symbols the app uses to PNGs for the video.
import AppKit

func render(_ name: String, _ out: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
        print("missing \(name)"); return
    }
    let pad: CGFloat = size * 0.1
    let canvas = NSSize(width: base.size.width + pad * 2, height: base.size.height + pad * 2)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width * 2), pixelsHigh: Int(canvas.height * 2),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    base.draw(in: NSRect(x: pad, y: pad, width: base.size.width, height: base.size.height))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
}

let blue = NSColor(red: 0.18, green: 0.45, blue: 0.93, alpha: 1)
let ink = NSColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 1)
let dir = CommandLine.arguments[1]
let items: [(String, String, NSColor)] = [
    ("cup.and.heat.waves.fill", "cup-on-blue", blue),
    ("cup.and.heat.waves.fill", "cup-on-ink", ink),
    ("cup.and.heat.waves.fill", "cup-on-white", .white),
    ("cup.and.saucer", "cup-off-ink", ink),
    ("battery.25percent", "battery-ink", ink),
    ("thermometer.medium", "thermo-ink", ink),
    ("moon.zzz", "moon-ink", ink),
    ("wifi", "wifi-ink", ink),
    ("battery.75percent", "battery75-ink", ink),
    ("apple.logo", "apple-ink", ink),
    ("magnifyingglass", "search-ink", ink),
    ("switch.2", "control-ink", ink),
]
for (name, file, color) in items {
    render(name, "\(dir)/\(file).png", size: 128, color: color)
}
