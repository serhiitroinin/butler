import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "Butler"
let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
// Every window, not only those on screen: the window may open on a Space or a
// workspace that is not showing, and a capture by id still works there. The
// main window is the largest; the app also owns small helper windows.
var found: [(area: Double, line: String)] = []
for window in list {
    guard window[kCGWindowOwnerName as String] as? String == owner,
          window[kCGWindowLayer as String] as? Int == 0,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double, height > 200,
          let number = window[kCGWindowNumber as String] as? Int else { continue }
    // The id, then the frame on screen: `1234 200 120 1180 760`.
    let frame = ["X", "Y", "Width", "Height"].map { String(Int((bounds[$0] as? Double) ?? 0)) }
    found.append((width * height, ([String(number)] + frame).joined(separator: " ")))
}
for entry in found.sorted(by: { $0.area > $1.area }) { print(entry.line) }
