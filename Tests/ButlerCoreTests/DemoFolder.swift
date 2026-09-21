import Foundation
import XCTest

/// Every test works in a throwaway folder under the temporary directory. No
/// test may ever point Butler at a real user folder.
final class DemoFolder {
    let root: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("butler-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func file(_ relative: String, contents: String = "data") throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    func folder(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(relative).path)
    }

    func read(_ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}
