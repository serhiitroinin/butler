import CoreGraphics
import Foundation
// Prints the id of the smallest on-screen Butler window: a menu or a popover.
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var best: (Int, Double)?
for w in list where w[kCGWindowOwnerName as String] as? String == "Butler" {
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let area = ((b["Width"] as? Double) ?? 0) * ((b["Height"] as? Double) ?? 0)
    guard area > 10_000, let id = w[kCGWindowNumber as String] as? Int else { continue }
    if best == nil || area < best!.1 { best = (id, area) }
}
if let best { print(best.0) }
