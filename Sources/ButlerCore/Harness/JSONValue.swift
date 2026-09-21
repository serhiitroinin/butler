import Foundation
import FoldHarnessV1

/// The generated JSON value carries every dynamic payload the sidecar sends.
public typealias JSONValue = FHInputValue

extension JSONValue {
    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        if case let .double(value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        guard let value = doubleValue, value.rounded() == value else { return nil }
        return Int(value)
    }

    public var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case let .unionArray(value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case let .unionMap(value) = self { return value }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    public static func object(_ value: [String: JSONValue]) -> JSONValue { .unionMap(value) }
    public static func array(_ value: [JSONValue]) -> JSONValue { .unionArray(value) }
    public static func number(_ value: Int) -> JSONValue { .double(Double(value)) }

    public func encodedString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let text = String(data: try encoder.encode(self), encoding: .utf8) else {
            throw ButlerError.message("The tool result could not be encoded as UTF-8 text.")
        }
        return text
    }
}

extension FHSchema {
    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        if case let .double(value) = self { return value }
        return nil
    }

    public var controlValue: JSONValue {
        switch self {
        case let .bool(value): return .bool(value)
        case let .double(value): return .double(value)
        case let .string(value): return .string(value)
        }
    }
}

public enum ButlerError: LocalizedError, Equatable {
    case message(String)

    public var errorDescription: String? {
        switch self {
        case let .message(text): return text
        }
    }
}
