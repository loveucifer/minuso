import AppKit
import Foundation
import ImageIO

guard CommandLine.arguments.count == 3 else {
    fputs("usage: make_icon.swift source.png output.icns\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
    throw NSError(domain: "MinusoIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read icon image at \(sourceURL.path)"])
}

let iconset = output.deletingPathExtension().appendingPathExtension("iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels
        ] as CFDictionary) else { continue }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { continue }
        let suffix = scale == 2 ? "@2x" : ""
        let filename = "icon_\(size)x\(size)\(suffix).png"
        try png.write(to: iconset.appendingPathComponent(filename), options: .atomic)
    }
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { throw NSError(domain: "MinusoIcon", code: Int(process.terminationStatus)) }
