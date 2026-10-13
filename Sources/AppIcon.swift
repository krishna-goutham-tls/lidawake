import AppKit
import SwiftUI

/// The Finder and Login Items icon. Drawn in code so it can be regenerated: `LidAwake --render-iconset dir`.
struct AppIconArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.white, Color(red: 0.90, green: 0.94, blue: 0.99)],
                    startPoint: .top, endPoint: .bottom
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 2)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)

            Image(systemName: "cup.and.heat.waves.fill")
                .font(.system(size: 400, weight: .regular))
                .foregroundStyle(LinearGradient(
                    colors: [Color(red: 0.27, green: 0.56, blue: 0.96), Color(red: 0.13, green: 0.38, blue: 0.82)],
                    startPoint: .top, endPoint: .bottom
                ))
                .offset(y: 10)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
func renderIconset(to directory: String) -> Bool {
    let sizes: [(String, CGFloat)] = [
        ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
        ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
        ("512x512", 512), ("512x512@2x", 1024),
    ]
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    for (name, pixels) in sizes {
        let renderer = ImageRenderer(content: AppIconArt().environment(\.colorScheme, .light))
        renderer.scale = pixels / 1024
        guard let image = renderer.cgImage else { return false }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("icon_\(name).png"))
        } catch {
            return false
        }
    }
    return true
}
