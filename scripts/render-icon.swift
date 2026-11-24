import AppKit

// Package the checked-in 1024 px artwork into the legacy macOS ICNS format.
// The matching SVG is the editable master. Keep its PNG export in sync.
let args = CommandLine.arguments
let sourcePath = args.count > 1 ? args[1] : "Artwork/AppIconSource.png"
let outputPath = args.count > 2 ? args[2] : "Artwork"
let tempPath = args.count > 3 ? args[3] : ".build/AppIcon.iconset"
let sourceURL = URL(fileURLWithPath: sourcePath)
let output = URL(fileURLWithPath: outputPath)
let iconset = URL(fileURLWithPath: tempPath)
guard let source = NSImage(contentsOf: sourceURL),
      let data = try? Data(contentsOf: sourceURL),
      let bitmap = NSBitmapImageRep(data: data),
      bitmap.pixelsWide == 1024, bitmap.pixelsHigh == 1024 else {
    fatalError("The icon source must be a 1024 x 1024 PNG: \(sourcePath)")
}
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func png(size: Int, to url: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    // ICNS does not receive Icon Composer's system mask. Supply a shared
    // rounded tile with the same 64 px transparent inset for all three apps.
    let tile = NSRect(x: 64, y: 64, width: 896, height: 896)
    NSBezierPath(roundedRect: tile, xRadius: 202, yRadius: 202).addClip()
    source.draw(in: tile, from: .zero, operation: .copy, fraction: 1,
                respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}
for size in [16, 32, 128, 256, 512] {
    try png(size: size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try png(size: size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try png(size: 1024, to: output.appendingPathComponent("AppIcon.png"))
try png(size: 256, to: output.appendingPathComponent("Preview.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try task.run()
task.waitUntilExit()
if task.terminationStatus != 0 { exit(task.terminationStatus) }
print("Generated \(outputPath)/AppIcon.icns")
