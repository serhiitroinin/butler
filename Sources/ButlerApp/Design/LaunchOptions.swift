import AppKit
import ButlerCore
import SwiftUI

/// Development switches used to capture every screen without driving the
/// interface by hand. They change presentation only.
enum LaunchOptions {
    private static let arguments = ProcessInfo.processInfo.arguments

    static var page: String? { value(for: "--page") }
    static var stage: StageMode? {
        value(for: "--stage").flatMap { name in
            StageMode.allCases.first { $0.rawValue.lowercased() == name.lowercased() }
        }
    }

    static var search: String? { value(for: "--search") }
    /// How many rows to select once a plan arrives.
    static var selectedRows: Int {
        if let count = value(for: "--select").flatMap(Int.init) { return count }
        return arguments.contains("--select-first") ? 1 : 0
    }
    /// Text to put in the change-request field once a plan arrives.
    static var ask: String? { value(for: "--ask") }
    static var hidesGrain: Bool { arguments.contains("--no-grain") }
    /// Seconds to wait before each file operation, so the applying state can
    /// be seen and captured. Development only.
    static var applyDelay: TimeInterval {
        (ProcessInfo.processInfo.environment["BUTLER_APPLY_DELAY_MS"].flatMap(Double.init) ?? 0) / 1000
    }
    static var opensQuickLook: Bool { arguments.contains("--quicklook") }
    /// A tiling window manager leaves a window alone when it cannot resize it.
    static var fixedSize: Bool { arguments.contains("--fixed-size") }

    static var appearance: NSAppearance? {
        switch value(for: "--appearance") {
        case "dark": return NSAppearance(named: .darkAqua)
        case "light": return NSAppearance(named: .aqua)
        default: return nil
        }
    }

    static func apply() {
        if let appearance { NSApp.appearance = appearance }
    }

    private static func value(for name: String) -> String? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
