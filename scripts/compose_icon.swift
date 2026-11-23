// compose_icon.swift <from.png> <to.png> <out.png>
//
// Draws a 256×256 route icon: the source app at the top left and the
// destination app, in front of it, at the bottom right.
// Run through `scripts/build.py --icons`.

import AppKit

let args = CommandLine.arguments
guard args.count == 4,
      let from = NSImage(contentsOfFile: args[1]),
      let to = NSImage(contentsOfFile: args[2]) else {
    FileHandle.standardError.write("usage: compose_icon.swift <from.png> <to.png> <out.png>\n".data(using: .utf8)!)
    exit(1)
}

let size = 256, part: CGFloat = 172
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high
// AppKit's origin is the bottom left.
from.draw(in: NSRect(x: 0, y: CGFloat(size) - part, width: part, height: part))
to.draw(in: NSRect(x: CGFloat(size) - part, y: 0, width: part, height: part))
NSGraphicsContext.restoreGraphicsState()

try bitmap.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: args[3]))
