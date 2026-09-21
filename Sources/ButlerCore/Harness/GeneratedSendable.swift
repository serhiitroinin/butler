import FoldHarnessV1

/// The generated bindings are immutable value trees of JSON data. They are safe
/// to send between actors; the generator does not declare it.
extension FHEvent: @unchecked Sendable {}
extension FHPayload: @unchecked Sendable {}
extension FHUsage: @unchecked Sendable {}
extension FHSession: @unchecked Sendable {}
extension FHInteraction: @unchecked Sendable {}
extension FHResponse: @unchecked Sendable {}
extension FHStepElement: @unchecked Sendable {}
extension FHInputValue: @unchecked Sendable {}
extension FHSidecarToolCallParamsClass: @unchecked Sendable {}
