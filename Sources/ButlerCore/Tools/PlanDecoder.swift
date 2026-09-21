import Foundation

/// Reads the untrusted `propose_plan` input. Every problem is reported at once
/// so the agent can fix the whole plan in one more turn.
enum PlanDecoder {
    static func decode(_ input: JSONValue) throws -> (summary: String, operations: [PlanOperation]) {
        guard let object = input.objectValue else {
            throw ButlerError.message("propose_plan takes an object with 'summary' and 'operations'.")
        }
        guard let summary = object["summary"]?.stringValue, !summary.isEmpty else {
            throw ButlerError.message("Write a short 'summary' of the plan for the user.")
        }
        guard let raw = object["operations"]?.arrayValue else {
            throw ButlerError.message("'operations' must be an array, even when it is empty.")
        }
        var operations: [PlanOperation] = []
        var problems: [String] = []
        for (index, element) in raw.enumerated() {
            do {
                operations.append(try operation(element, at: index))
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        guard problems.isEmpty else {
            throw ButlerError.message("Fix these operations and call propose_plan again:\n- "
                + problems.joined(separator: "\n- "))
        }
        return (summary, operations)
    }

    private static func operation(_ value: JSONValue, at index: Int) throws -> PlanOperation {
        let position = "operation \(index + 1)"
        guard let object = value.objectValue else {
            throw ButlerError.message("\(position): each operation must be an object.")
        }
        guard let name = object["op"]?.stringValue, let kind = OperationKind(rawValue: name) else {
            let allowed = OperationKind.allCases.map(\.rawValue).joined(separator: ", ")
            throw ButlerError.message("\(position): 'op' must be one of \(allowed).")
        }
        let reason = object["reason"]?.stringValue ?? ""
        switch kind {
        case .mkdir:
            guard let path = object["path"]?.stringValue, !path.isEmpty else {
                throw ButlerError.message("\(position): a mkdir needs 'path'.")
            }
            return PlanOperation(kind: .mkdir, destination: path, reason: reason)
        case .trash:
            guard let path = object["path"]?.stringValue, !path.isEmpty else {
                throw ButlerError.message("\(position): a trash needs 'path'.")
            }
            return PlanOperation(kind: .trash, source: path, reason: reason)
        case .move, .rename:
            guard let from = object["from"]?.stringValue, !from.isEmpty,
                  let to = object["to"]?.stringValue, !to.isEmpty else {
                throw ButlerError.message("\(position): a \(name) needs 'from' and 'to'.")
            }
            return PlanOperation(kind: kind, source: from, destination: to, reason: reason)
        }
    }
}
