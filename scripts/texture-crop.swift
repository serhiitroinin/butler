import AppKit
// Crops a rectangle of pixels from a screenshot, doubles it without smoothing,
// and prints how far the luminance strays from flat. Usage:
//   swift scripts/texture-crop.swift in.png out.png x y width height
let a = CommandLine.arguments
guard a.count == 7, let source = NSImage(contentsOfFile: a[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let x = Int(a[3]), let y = Int(a[4]), let w = Int(a[5]), let h = Int(a[6]),
      let crop = source.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
    FileHandle.standardError.write("usage: texture-crop.swift in.png out.png x y width height\n".data(using: .utf8)!)
    exit(1)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let info = CGImageAlphaInfo.premultipliedLast.rawValue
let big = CGContext(data: nil, width: w * 2, height: h * 2, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
big.interpolationQuality = .none
big.draw(crop, in: CGRect(x: 0, y: 0, width: w * 2, height: h * 2))
let rep = NSBitmapImageRep(cgImage: big.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))

let small = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: info)!
small.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
let bytes = small.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
var values: [Double] = []
for i in 0..<(w * h) {
    values.append(0.2126 * Double(bytes[i * 4]) + 0.7152 * Double(bytes[i * 4 + 1]) + 0.0722 * Double(bytes[i * 4 + 2]))
}
let mean = values.reduce(0, +) / Double(values.count)
let deviation = (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
print(String(format: "mean %.1f  sd %.2f (%.1f%% of full scale)  range %.0f–%.0f", mean, deviation, deviation / 255 * 100, values.min()!, values.max()!))
