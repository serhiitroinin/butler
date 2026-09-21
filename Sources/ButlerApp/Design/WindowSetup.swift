import AppKit
import SwiftUI

/// Gives the window a deterministic first size, then lets the user's own size
/// persist, and makes the whole frame one sheet of stock: a transparent
/// titlebar over the paper colour, with the grain on top.
struct WindowSetup: NSViewRepresentable {
    static let autosaveName = "ButlerMainWindow"
    static let firstSize = NSSize(width: 1180, height: 760)
    static let minimumSize = NSSize(width: 940, height: 600)
    private static var sizeKeeper: NSObjectProtocol?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { Self.configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { Chrome.refresh(view.window) }
    }

    static func configure(_ window: NSWindow?) {
        guard let window else { return }
        Chrome.dress(window)
        guard window.frameAutosaveName != autosaveName else { return }
        if LaunchOptions.fixedSize {
            window.setFrame(NSRect(x: 200, y: 120, width: firstSize.width, height: firstSize.height), display: true)
            window.styleMask.remove(.resizable)
            /// A tiling window manager resizes through accessibility, which a
            /// missing resize control does not stop. The size limits do, and
            /// the observer puts back whatever still gets through.
            window.minSize = firstSize
            window.maxSize = firstSize
            guard sizeKeeper == nil else { return }
            sizeKeeper = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: window, queue: .main
            ) { [weak window] _ in
                guard let window, window.frame.size != firstSize else { return }
                window.setFrame(NSRect(origin: window.frame.origin, size: firstSize), display: true)
            }
            return
        }
        window.minSize = minimumSize
        let restored = UserDefaults.standard.object(forKey: "NSWindow Frame \(autosaveName)") != nil
        window.setFrameAutosaveName(autosaveName)
        guard !restored else { return }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = NSSize(
            width: min(firstSize.width, visible.width),
            height: min(firstSize.height, visible.height)
        )
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        window.saveFrame(usingName: autosaveName)
    }
}

/// The few places where a system control has to be told about the stock: the
/// titlebar and the sidebar's own selection highlight.
enum Chrome {
    static func dress(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Stock.paperNS
        GrainView.install(in: window)
        refresh(window)
    }

    static func refresh(_ window: NSWindow?) {
        guard let root = window?.contentView?.superview else { return }
        for view in descendants(of: root) {
            if let outline = view as? NSOutlineView, outline.selectionHighlightStyle != .none {
                outline.selectionHighlightStyle = .none
            }
        }
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
