import AppKit
// Says whether a window capture shows the key window: the close button is red
// only then. Usage: swift scripts/window-active.swift shot.png... ; exits 1 if
// any capture shows an inactive window.
var inactive = 0
for path in CommandLine.arguments.dropFirst() {
    guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("\(path): unreadable"); inactive += 1; continue
    }
    let rep = NSBitmapImageRep(cgImage: image)
    let scale = image.width >= 2000 ? 2 : 1
    guard let colour = rep.colorAt(x: 19 * scale, y: 19 * scale)?.usingColorSpace(.sRGB) else { continue }
    let active = colour.redComponent > 0.75 && colour.greenComponent < 0.55
    if !active { inactive += 1 }
    print("\(path): \(image.width)x\(image.height) \(active ? "active" : "INACTIVE")")
}
exit(inactive == 0 ? 0 : 1)
