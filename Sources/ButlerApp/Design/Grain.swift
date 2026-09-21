import AppKit

/// Paper tooth for the whole window: a tile of procedural noise drawn over
/// everything at a few per cent. It is never a photograph, it takes no clicks,
/// and it goes away when the user asks for less transparency or more contrast.
final class GrainView: NSView {
    private static var tiles: [String: CGImage] = [:]
    private static let tilePoints = 384

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        layerContentsRedrawPolicy = .duringViewResize
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(optionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        optionsChanged()
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
    override func viewDidChangeBackingProperties() { needsDisplay = true }

    @objc private func optionsChanged() {
        let workspace = NSWorkspace.shared
        isHidden = workspace.accessibilityDisplayShouldReduceTransparency
            || workspace.accessibilityDisplayShouldIncreaseContrast
            || LaunchOptions.hidesGrain
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let scale = max(1, Int((window?.backingScaleFactor ?? 2).rounded()))
        guard let tile = Self.tile(dark: dark, scale: scale) else { return }
        let side = CGFloat(Self.tilePoints)
        context.interpolationQuality = .none
        context.draw(tile, in: CGRect(x: 0, y: 0, width: side, height: side), byTiling: true)
    }

    static func install(in window: NSWindow) {
        guard let frame = window.contentView?.superview else { return }
        guard !frame.subviews.contains(where: { $0 is GrainView }) else { return }
        let grain = GrainView(frame: frame.bounds)
        frame.addSubview(grain, positioned: .above, relativeTo: nil)
    }

    private static func tile(dark: Bool, scale: Int) -> CGImage? {
        let key = "\(dark)-\(scale)"
        if let cached = tiles[key] { return cached }
        let image = makeTile(side: tilePoints * scale, scale: scale, dark: dark)
        tiles[key] = image
        return image
    }

    /// Two layers, both wrapping at the tile edge: an even tooth and a very
    /// soft, wide mottle. No fibres and no specks: clean stock, not recycled.
    private static func makeTile(side: Int, scale: Int, dark: Bool) -> CGImage? {
        var random = Lehmer(seed: dark ? 0x51F15EED : 0x2545F491)
        let strength = dark ? 0.08 : 0.12
        let cell = 24 * scale
        let cells = side / cell
        let coarse = (0..<(cells * cells)).map { _ in random.signed() }
        func mottle(_ x: Int, _ y: Int) -> Double {
            let fx = Double(x) / Double(cell), fy = Double(y) / Double(cell)
            let x0 = Int(fx) % cells, y0 = Int(fy) % cells
            let x1 = (x0 + 1) % cells, y1 = (y0 + 1) % cells
            let tx = fx - floor(fx), ty = fy - floor(fy)
            let top = coarse[y0 * cells + x0] * (1 - tx) + coarse[y0 * cells + x1] * tx
            let bottom = coarse[y1 * cells + x0] * (1 - tx) + coarse[y1 * cells + x1] * tx
            return top * (1 - ty) + bottom * ty
        }

        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        // Tooth one point across survives a Retina screen; tooth one pixel
        // across alone would average away to nothing.
        let points = side / scale
        let tooth = (0..<(points * points)).map { _ in random.signed() }
        var previous = 0.0
        for y in 0..<side {
            for x in 0..<side {
                // Two draws averaged pull the tooth toward the middle, so no
                // single pixel stands out as a speck.
                let pixel = (random.signed() + random.signed()) * 0.5
                let fresh = pixel * 0.5 + tooth[(y / scale) * points + x / scale] * 0.5
                // A little horizontal drag gives the tooth a grain direction.
                let fine = fresh * 0.7 + previous * 0.3
                previous = fresh
                let value = fine * 0.9 + mottle(x, y) * 0.1
                // Shade weighs less than light: dark flecks are what read as dirt.
                let weight = value > 0 ? 1.0 : (dark ? 0.8 : 0.45)
                let alpha = UInt8(min(255, abs(value) * weight * strength * 255))
                let offset = (y * side + x) * 4
                let lit: UInt8 = value > 0 ? alpha : 0
                pixels[offset] = lit
                pixels[offset + 1] = lit
                pixels[offset + 2] = lit
                pixels[offset + 3] = alpha
            }
        }

        return context.makeImage()
    }
}

/// A small deterministic generator, so the paper is the same on every launch.
private struct Lehmer {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func unit() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0xFFFFFF) / Double(0x1000000)
    }

    mutating func signed() -> Double { unit() * 2 - 1 }
}
