import AppKit
// Captures the app's main window and its open menu by window id and lays the
// menu over the window where it sits on screen. A screen-region capture shows
// whatever else is on the screen; this shows only the app's own windows.
// Usage: swift scripts/menu-composite.swift out.png [owner]
let arguments = CommandLine.arguments
guard arguments.count >= 2 else { FileHandle.standardError.write("usage: menu-composite.swift out.png [owner]\n".data(using: .utf8)!); exit(1) }
let owner = arguments.count > 2 ? arguments[2] : "Butler"

struct Found { let id: Int; let frame: CGRect; let layer: Int }
let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let windows: [Found] = list.compactMap { window in
    guard window[kCGWindowOwnerName as String] as? String == owner,
          let id = window[kCGWindowNumber as String] as? Int,
          let layer = window[kCGWindowLayer as String] as? Int,
          layer == 0 || window[kCGWindowIsOnscreen as String] as? Bool == true,
          let bounds = window[kCGWindowBounds as String] as? NSDictionary,
          let frame = CGRect(dictionaryRepresentation: bounds), frame.width > 60, frame.height > 60 else { return nil }
    return Found(id: id, frame: frame, layer: layer)
}
guard let main = windows.filter({ $0.layer == 0 }).max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
    FileHandle.standardError.write("no main window\n".data(using: .utf8)!); exit(1)
}
// A menu lives above the normal layer. With several displays and a tiling
// window manager the system sometimes opens it on the display above: its x is
// still the button's, its y is not. It is then drawn where a pull-down opens,
// right under the toolbar button.
let menus = windows.filter { $0.layer > 0 && $0.frame.maxX > main.frame.minX && $0.frame.minX < main.frame.maxX }
guard let menu = menus.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
    FileHandle.standardError.write("no open menu\n".data(using: .utf8)!); exit(2)
}
let underToolbar: CGFloat = 35
let menuTop = menu.frame.intersects(main.frame) ? menu.frame.minY - main.frame.minY : underToolbar

func capture(_ id: Int) -> CGImage? {
    let path = NSTemporaryDirectory() + "butler-window-\(id).png"
    defer { try? FileManager.default.removeItem(atPath: path) }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-o", "-x", "-l", String(id), path]
    try? task.run()
    task.waitUntilExit()
    return NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
}
guard let window = capture(main.id), let overlay = capture(menu.id) else {
    FileHandle.standardError.write("capture failed\n".data(using: .utf8)!); exit(1)
}
let scale = CGFloat(window.width) / main.frame.width
let context = CGContext(
    data: nil, width: window.width, height: window.height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
context.draw(window, in: CGRect(x: 0, y: 0, width: window.width, height: window.height))
// Window frames have a top-left origin; the context's is bottom-left.
let x = (menu.frame.minX - main.frame.minX) * scale
let top = menuTop * scale
let target = CGRect(x: x, y: CGFloat(window.height) - top - CGFloat(overlay.height), width: CGFloat(overlay.width), height: CGFloat(overlay.height))
// A soft shadow, since the capture by id leaves the system's own out.
context.setShadow(offset: CGSize(width: 0, height: -6 * scale), blur: 18 * scale, color: CGColor(gray: 0, alpha: 0.28))
context.draw(overlay, in: target)
let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[1]))
