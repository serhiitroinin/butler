import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Bounded metadata and a short preview. Butler never sends a whole file to a
/// provider.
public struct FileInspector: Sendable {
    public static let previewBytes = 2048
    public static let pdfTextCharacters = 900

    private let guardrail: PathGuard

    public init(guardrail: PathGuard) {
        self.guardrail = guardrail
    }

    public func inspect(path: String) throws -> [String: JSONValue] {
        let url = try guardrail.resolve(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ButlerError.message("\(path): there is no such file.")
        }
        guard !isDirectory.boolValue else {
            throw ButlerError.message("\(path): that is a folder. Use list_folder for a folder.")
        }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .contentTypeKey]
        let values = try url.resourceValues(forKeys: keys)
        let type = values.contentType
        var result: [String: JSONValue] = [
            "path": .string(path),
            "name": .string(url.lastPathComponent),
            "extension": .string(url.pathExtension.lowercased()),
        ]
        if let size = values.fileSize { result["sizeBytes"] = .number(size) }
        if let type { result["type"] = .string(type.identifier) }
        if let created = values.creationDate { result["created"] = .string(Self.stamp(created)) }
        if let modified = values.contentModificationDate { result["modified"] = .string(Self.stamp(modified)) }

        if let type, type.conforms(to: .pdf) {
            merge(&result, pdf(url))
        } else if let type, type.conforms(to: .image) {
            merge(&result, image(url))
        } else if isTextLike(type) {
            if let preview = textPreview(url) { result["preview"] = .string(preview) }
        } else {
            result["preview"] = .string("Butler does not read this file type.")
        }
        return result
    }

    private func merge(_ target: inout [String: JSONValue], _ extra: [String: JSONValue]) {
        for (key, value) in extra { target[key] = value }
    }

    private func isTextLike(_ type: UTType?) -> Bool {
        guard let type else { return false }
        return type.conforms(to: .text) || type.conforms(to: .json) || type.conforms(to: .xml)
    }

    private func textPreview(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.previewBytes), !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private func pdf(_ url: URL) -> [String: JSONValue] {
        guard let document = PDFDocument(url: url) else { return [:] }
        var result: [String: JSONValue] = ["pageCount": .number(document.pageCount)]
        if let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
           !title.isEmpty {
            result["title"] = .string(title)
        }
        if let text = document.page(at: 0)?.string, !text.isEmpty {
            result["preview"] = .string(String(text.prefix(Self.pdfTextCharacters)))
        }
        return result
    }

    private func image(_ url: URL) -> [String: JSONValue] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return [:]
        }
        var result: [String: JSONValue] = [:]
        if let width = properties[kCGImagePropertyPixelWidth] as? Int { result["pixelWidth"] = .number(width) }
        if let height = properties[kCGImagePropertyPixelHeight] as? Int { result["pixelHeight"] = .number(height) }
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let taken = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            result["photoTakenAt"] = .string(taken)
        }
        return result
    }

    static func stamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
