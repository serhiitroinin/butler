import Foundation

enum ToolCatalog {
    static let listFolder = "list_folder"
    static let inspectFile = "inspect_file"
    static let proposePlan = "propose_plan"

    static var descriptors: [Harness.ToolDescriptor] {
        [
            Harness.ToolDescriptor(
                name: listFolder,
                description: """
                List the items of one folder. Every path is relative to the managed folder; \
                use "." for the top level. Returns name, kind, size, dates and, for a folder, \
                the number of items. The listing is bounded and hidden items never appear.
                """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("A folder path relative to the managed folder."),
                        ]),
                        "depth": .object([
                            "type": .string("integer"),
                            "minimum": .number(1),
                            "maximum": .number(3),
                        ]),
                    ]),
                    "required": .array([.string("path")]),
                    "additionalProperties": .bool(false),
                ])
            ),
            Harness.ToolDescriptor(
                name: inspectFile,
                description: """
                Read bounded metadata for one file: size, dates, type, image size and date, \
                PDF title and first page text, or the first two kilobytes of a text file. \
                Butler never reads a whole file.
                """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("A file path relative to the managed folder."),
                        ]),
                    ]),
                    "required": .array([.string("path")]),
                    "additionalProperties": .bool(false),
                ])
            ),
            Harness.ToolDescriptor(
                name: proposePlan,
                description: """
                Record the organisation plan and end the turn. This is the only way to \
                change anything, and it changes nothing by itself: the user reviews the plan \
                and approves it. Operations run in order. Use "mkdir" before you move files \
                into a new folder. Use "move" to put a file in another folder, "rename" to \
                change a name inside the same folder, and "trash" only with a strong reason. \
                Every move, rename, and trash needs a short "reason".
                """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "summary": .object([
                            "type": .string("string"),
                            "description": .string("One short paragraph for the user."),
                        ]),
                        "operations": .object([
                            "type": .string("array"),
                            "items": .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "op": .object([
                                        "type": .string("string"),
                                        "enum": .array(OperationKind.allCases.map { .string($0.rawValue) }),
                                    ]),
                                    "path": .object(["type": .string("string")]),
                                    "from": .object(["type": .string("string")]),
                                    "to": .object(["type": .string("string")]),
                                    "reason": .object(["type": .string("string")]),
                                ]),
                                "required": .array([.string("op")]),
                                "additionalProperties": .bool(false),
                            ]),
                        ]),
                    ]),
                    "required": .array([.string("summary"), .string("operations")]),
                    "additionalProperties": .bool(false),
                ])
            ),
        ]
    }
}
