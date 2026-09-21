import Foundation

/// The generated bindings decode every sidecar answer. These small request
/// values exist because the generated parameter types require every optional
/// field at the call site, which reads badly for the few requests Butler sends.
enum Harness {
    struct Request<Params: Encodable>: Encodable {
        let jsonrpc = "2.0"
        let id: Int
        let method: String
        let params: Params
    }

    struct Response<Result: Encodable>: Encodable {
        let jsonrpc = "2.0"
        let id: Int
        let result: Result
    }

    struct Empty: Encodable {}

    struct ClientInfo: Encodable {
        let name: String
        let version: String
    }

    struct InitializeParams: Encodable {
        let protocolVersion = 1
        let client: ClientInfo
    }

    struct DiscoveryParams: Encodable {
        let schemaVersion = 1
        let adapterId: String
    }

    struct SessionKey: Encodable, Sendable {
        let tenantId: String
        let actorId: String
        let threadId: String
    }

    struct TextInput: Encodable {
        let type = "text"
        let text: String
    }

    struct PermissionSelection: Encodable {
        let modeId: String
    }

    struct RunSettings: Encodable {
        var permission: PermissionSelection?
        var controls: [String: JSONValue]?
    }

    struct RunRequest: Encodable {
        let schemaVersion = 1
        let session: SessionKey
        let adapterId: String
        let input: [TextInput]
        var model: String?
        var effort: String?
        var settings: RunSettings?
    }

    struct ContextValue: Encodable {
        var instructions: String?
        var content: [TextInput] = []
    }

    struct ContextSource: Encodable {
        let sourceId: String
        let value: ContextValue
    }

    struct PreparedContext: Encodable {
        var sources: [ContextSource] = []
        var unavailable: [String] = []
    }

    struct ToolDescriptor: Encodable {
        let name: String
        let description: String
        let inputSchema: JSONValue
    }

    struct RunStartParams: Encodable {
        let request: RunRequest
        var tools: [ToolDescriptor]
        var context: PreparedContext
    }

    struct RunParams: Encodable {
        let runId: String
    }

    struct ToolResultContent: Encodable {
        let type = "text"
        let text: String
    }

    struct ToolResult: Encodable {
        let content: [ToolResultContent]
        var isError: Bool?
        var code: String?

        static func text(_ value: String) -> ToolResult {
            ToolResult(content: [ToolResultContent(text: value)])
        }

        static func failure(_ value: String, code: String) -> ToolResult {
            ToolResult(content: [ToolResultContent(text: value)], isError: true, code: code)
        }
    }
}
