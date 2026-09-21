import ButlerCore
import Combine
import SwiftUI

struct ApplyProgress: Equatable {
    var completed: Int
    var total: Int
    var current: String
}

@MainActor
final class FolderViewModel: ObservableObject {
    let folderId: UUID
    @Published private(set) var run: RunController
    @Published private(set) var selection: PlanSelection?
    @Published private(set) var applying: ApplyProgress?
    @Published var changeRequest = ""
    @Published var error: String?
    @Published var sheetSelection: Set<String> = []
    @Published private(set) var appliedRecordId: UUID?

    /// An older revision on show, read-only. `nil` means the latest.
    @Published var shownRevision: Int?

    let presentation = ProposalPresentation()
    private var wasRunning = false
    private var groupCache: [String: [PlanTableNode]] = [:]
    private let store: ButlerStore
    private let service: HarnessService
    private var cancellables: Set<AnyCancellable> = []

    init(folderId: UUID, store: ButlerStore, service: HarnessService) {
        self.folderId = folderId
        self.store = store
        self.service = service
        run = RunController(service: service)
        observe()
        rebuildSelection()
        restoreStatus()
    }

    var folder: ManagedFolder? { store.folder(folderId) }
    var plan: Plan? {
        if let shownRevision, let older = folder?.revisions.first(where: { $0.revision == shownRevision }) {
            return older
        }
        return folder?.currentPlan
    }

    var isLatestRevision: Bool { plan?.id == folder?.currentPlan?.id }
    var canDecide: Bool { isLatestRevision && !isBusy && status != .approved && stoppedRun == nil }

    /// An apply that stopped at a failure and left items moved. Until it is
    /// undone the plan no longer matches the folder, so nothing can be decided.
    var stoppedRun: RunRecord? {
        guard let plan = folder?.currentPlan,
              let record = folder?.history.first(where: { $0.plan.id == plan.id && $0.rejected != true }),
              record.failure != nil, record.canUndo
        else { return nil }
        return record
    }
    var isBusy: Bool { run.phase.isRunning || applying != nil }

    var includedCount: Int { selection?.includedCount ?? 0 }
    var canRun: Bool { !isBusy && folder != nil }
    var lastUndoableRun: RunRecord? { folder?.history.first { $0.canUndo } }
    var failures: [ActivityLine] { run.activity.filter { $0.kind == .failure } }
    var showsBottomBar: Bool { plan != nil || applying != nil || lastUndoableRun != nil }
    var appliedRecord: RunRecord? {
        guard let appliedRecordId else { return nil }
        return folder?.history.first { $0.id == appliedRecordId }
    }

    /// The one line under the window title.
    var stateLine: String {
        if applying != nil { return "Applying…" }
        if run.phase.isRunning { return "Organising…" }
        if let plan { return Format.count(plan.operations.count, "change", "changes") + " proposed" }
        if let record = folder?.history.first(where: { $0.undoneAt == nil && $0.rejected != true }) {
            return "Tidied " + record.appliedAt.formatted(date: .omitted, time: .shortened)
        }
        return "No proposal"
    }

    /// The bottom bar's left label.
    var statusLine: String {
        if run.phase.isRunning { return run.activity.last?.text ?? "Reading the folder…" }
        if let record = lastUndoableRun, plan == nil {
            return "Tidied · \(Format.count(record.itemCount, "item", "items"))"
        }
        guard let plan else { return "" }
        var moves = Format.count(plan.count(of: .move), "move", "moves")
        if let source = commonSource {
            moves += source.isEmpty || source == "Top Level" ? " from the top level" : " from \(source)"
        }
        var parts = [moves, Format.count(plan.count(of: .mkdir), "new folder", "new folders")]
        if plan.count(of: .rename) > 0 { parts.append(Format.count(plan.count(of: .rename), "rename", "renames")) }
        parts.append(plan.count(of: .trash) == 0
            ? "nothing to Trash"
            : Format.count(plan.count(of: .trash), "item to Trash", "items to Trash"))
        let excluded = plan.operations.count - includedCount
        if excluded > 0 { parts.append("\(excluded) excluded") }
        return parts.joined(separator: " · ")
    }

    /// The one folder every moved file comes from, when there is only one.
    var commonSource: String? {
        guard let plan, let root = folder?.url else { return nil }
        return PlanTable.commonSource(
            in: PlanTable.nodes(mode: .changes, plan: plan, included: includedOperations, root: root)
        )
    }

    func state(of operationIds: [UUID]) -> InclusionState {
        guard let plan, let selection else { return .included }
        return selection.state(of: operationIds, in: plan)
    }
    var includedOperations: [PlanOperation] { selection?.included ?? [] }

    func isIncluded(_ operation: PlanOperation) -> Bool {
        selection?.isIncluded(operation) ?? false
    }

    func isIncluded(_ operationId: UUID?) -> Bool {
        guard let operationId, let operation = operation(operationId) else { return true }
        return isIncluded(operation)
    }

    func blockReason(_ operationId: UUID?) -> String? {
        guard let operationId, let operation = operation(operationId) else { return nil }
        return selection?.blockReason(operation)
    }

    func setIncluded(_ operationIds: [UUID], to included: Bool) {
        guard let plan, canDecide else { return }
        selection?.setIncluded(operationIds, to: included, in: plan)
        objectWillChange.send()
    }

    /// Include or exclude the rows selected in the table.
    func setSelectionIncluded(_ included: Bool) {
        let ids = groups(mode: .changes)
            .flatMap { [$0] + ($0.children ?? []) }
            .filter { sheetSelection.contains($0.id) }
            .flatMap(\.operationIds)
        setIncluded(ids, to: included)
    }

    /// The table's groups. Building them stats every file, so they are kept
    /// until the plan or the inclusion set changes.
    func groups(mode: StageMode) -> [PlanTableNode] {
        guard let plan, let root = folder?.url else { return [] }
        let key = mode == .changes
            ? "\(plan.id)-changes"
            : "\(plan.id)-\(mode.rawValue)-\(selection?.excluded.hashValue ?? 0)"
        if let cached = groupCache[key] { return cached }
        let built = PlanTable.destinations(mode: mode, plan: plan, included: includedOperations, root: root)
        if groupCache.count > 8 { groupCache.removeAll() }
        groupCache[key] = built
        return built
    }

    func show(revision: Int) {
        shownRevision = revision == folder?.currentPlan?.revision ? nil : revision
        sheetSelection = []
        rebuildSelection()
    }

    private func operation(_ id: UUID) -> PlanOperation? {
        plan?.operations.first { $0.id == id }
    }

    func startRun() {
        guard let folder, !isBusy else { return }
        error = nil
        shownRevision = nil
        groupCache.removeAll()
        presentation.reset()
        presentation.apply(.runStarted)
        store.update(folderId) { $0.revisions = [] }
        let revision = (folder.currentPlan?.revision ?? 0) + 1
        let options = RunRequestOptions(
            folderId: folder.id,
            root: folder.url,
            rules: folder.rules,
            choice: choice(for: folder),
            revision: revision
        )
        Task { await run.start(options) }
    }

    func requestChanges() {
        let text = changeRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let folder, let plan, !text.isEmpty, canDecide else { return }
        error = nil
        changeRequest = ""
        let excluded = plan.operations.filter { !(selection?.isIncluded($0) ?? true) }
        presentation.pendingRequest = text
        presentation.apply(.runStarted)
        let options = RunRequestOptions(
            folderId: folder.id,
            root: folder.url,
            rules: folder.rules,
            choice: choice(for: folder),
            review: ReviewContext(plan: plan, excluded: excluded, request: text),
            revision: plan.revision + 1
        )
        Task { await run.start(options) }
    }

    func stop() {
        Task { await run.stop() }
    }

    func reject() {
        guard let plan = folder?.currentPlan, !isBusy else { return }
        presentation.reset(to: .rejected)
        shownRevision = nil
        store.update(folderId) {
            $0.history.insert(RunRecord(plan: plan, actions: [], appliedCount: 0, rejected: true), at: 0)
            $0.revisions = []
        }
        selection = nil
        objectWillChange.send()
    }

    /// The applier works off the main actor and reports before each
    /// operation, so the page dims exactly what has really been done.
    func approve(undoManager: UndoManager?) {
        guard let folder, let plan, let selection, canDecide else { return }
        let operations = selection.included
        guard !operations.isEmpty else { return }
        applying = ApplyProgress(completed: 0, total: operations.count, current: "")
        presentation.beginApplying(operations)
        let applier = PlanApplier(guardrail: PathGuard(root: folder.url))
        let delay = LaunchOptions.applyDelay
        let last = LastIndex()
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                applier.apply(operations) { index, operation in
                    if delay > 0 { Thread.sleep(forTimeInterval: delay) }
                    last.set(index)
                    Task { @MainActor in self.applierReached(index, operation, of: operations.count) }
                }
            }.value
            finishApply(outcome, plan: plan, count: operations.count, stoppedAt: last.value, undoManager: undoManager)
        }
    }

    private func applierReached(_ index: Int, _ operation: PlanOperation, of total: Int) {
        guard applying != nil else { return }
        applying = ApplyProgress(completed: index, total: total, current: operation.displayName)
        presentation.reached(index)
    }

    private func finishApply(
        _ outcome: ApplyOutcome,
        plan: Plan,
        count: Int,
        stoppedAt index: Int,
        undoManager: UndoManager?
    ) {
        let record = RunRecord(
            plan: plan,
            actions: outcome.actions,
            appliedCount: count,
            failure: outcome.failure
        )
        store.update(folderId) { $0.history.insert(record, at: 0) }
        applying = nil
        error = record.failure
        registerUndo(record, with: undoManager)
        appliedRecordId = record.id
        presentation.finishApplying(outcome, stoppedAt: outcome.succeeded ? count : index)
        objectWillChange.send()
    }

    /// The error with what really happened before it, for the bottom bar:
    /// `… 9 items were moved before it; Undo puts them back.`
    var stoppedLine: String? {
        guard let failure = presentation.failure else { return nil }
        let moved = stoppedRun?.itemCount ?? 0
        let tail = moved == 0
            ? "Nothing was moved."
            : "\(Format.count(moved, "item was", "items were")) moved before it; Undo puts \(moved == 1 ? "it" : "them") back."
        return (failure.hasSuffix(".") ? failure : failure + ".") + " " + tail
    }

    private func registerUndo(_ record: RunRecord, with undoManager: UndoManager?) {
        guard let undoManager, outcomeIsUndoable(record) else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.undo(record)
        }
        undoManager.setActionName("Organise")
    }

    private func outcomeIsUndoable(_ record: RunRecord) -> Bool {
        !record.actions.isEmpty
    }

    func undoLastRun() {
        guard let record = lastUndoableRun else { return }
        undo(record)
    }

    func undo(_ record: RunRecord) {
        guard let folder, !isBusy else { return }
        let applier = PlanApplier(guardrail: PathGuard(root: folder.url))
        let outcome = applier.undo(record.actions)
        let wasStopped = record.failure != nil && record.undoneAt == nil
        store.update(folderId) { value in
            guard let index = value.history.firstIndex(where: { $0.id == record.id }) else { return }
            if outcome.succeeded { value.history[index].undoneAt = Date() }
            /// Why a run stopped stays on its record; only a failed undo replaces it.
            if let failure = outcome.failure { value.history[index].failure = failure }
        }
        error = outcome.failure
        if outcome.succeeded, record.plan.id == folder.currentPlan?.id {
            if wasStopped {
                /// Nothing of the plan is applied any more: it is a proposal again.
                presentation.reset()
            } else {
                presentation.apply(.undone)
                presentation.clearTrace()
            }
        }
        objectWillChange.send()
    }

    /// Puts an undone run back, from the journal of what it really did.
    func redo(_ record: RunRecord) {
        guard let folder, !isBusy, record.undoneAt != nil else { return }
        let operations = record.actions.compactMap { action -> PlanOperation? in
            switch action.kind {
            case .moved: return PlanOperation(kind: .move, source: action.source, destination: action.destination)
            case .trashed: return PlanOperation(kind: .trash, source: action.source)
            case .createdFolder: return nil
            }
        }
        guard !operations.isEmpty else { return }
        let outcome = PlanApplier(guardrail: PathGuard(root: folder.url)).apply(operations)
        let again = RunRecord(
            plan: record.plan,
            actions: outcome.actions,
            appliedCount: operations.count,
            failure: outcome.failure
        )
        store.update(folderId) { $0.history.insert(again, at: 0) }
        error = outcome.failure
        if outcome.succeeded, record.plan.id == folder.currentPlan?.id {
            presentation.restore(applied: record.plan.operations, undone: false, count: operations.count)
        }
        objectWillChange.send()
    }

    func updateRules(_ text: String) {
        store.update(folderId) { $0.rules = text }
    }

    func updateChoice(_ choice: EngineChoice) {
        store.update(folderId) { $0.choice = choice }
    }

    private func choice(for folder: ManagedFolder) -> EngineChoice {
        var choice = folder.choice.isEmpty ? store.settings.choice : folder.choice
        if choice.engineId == nil { choice.engineId = service.defaultEngineId }
        return choice
    }

    private func observe() {
        presentation.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        run.objectWillChange
            .sink { [weak self] in
                Task { @MainActor [weak self] in self?.runChanged() }
            }
            .store(in: &cancellables)
        store.objectWillChange
            .sink { [weak self] in
                Task { @MainActor [weak self] in self?.objectWillChange.send() }
            }
            .store(in: &cancellables)
    }

    private func runChanged() {
        objectWillChange.send()
        if wasRunning, !run.phase.isRunning, let folder {
            /// The turn spent some of the account's allowance.
            let engineId = choice(for: folder).engineId
            Task { await service.refresh(engine: engineId) }
        }
        wasRunning = run.phase.isRunning
        guard case .proposed = run.phase, let plan = run.plan else {
            if case let .failed(message) = run.phase {
                error = message
                presentation.pendingRequest = nil
                presentation.apply(.runFailed)
            }
            return
        }
        guard folder?.currentPlan?.id != plan.id else { return }
        store.update(folderId) { $0.revisions.append(plan) }
        shownRevision = nil
        presentation.pendingRequest = nil
        presentation.apply(.planArrived)
        rebuildSelection()
        if let text = LaunchOptions.ask, plan.revision == 1 { changeRequest = text }
    }

    /// A plan applied in an earlier session is still shown as applied.
    private func restoreStatus() {
        guard let plan = folder?.currentPlan,
              let record = folder?.history.first(where: { $0.plan.id == plan.id && $0.rejected != true })
        else { return }
        let touched = Set(record.actions.map(\.source))
        if let failure = record.failure {
            /// A stopped run that was undone is a plain proposal again.
            guard record.canUndo else { return }
            let applied = plan.operations.filter {
                touched.contains($0.kind == .mkdir ? $0.destination : $0.source)
            }
            presentation.restore(stopped: applied, failure: failure)
            return
        }
        let applied = plan.operations.filter { $0.kind == .mkdir || touched.contains($0.source) }
        presentation.restore(applied: applied, undone: record.undoneAt != nil, count: record.itemCount)
    }

    private func rebuildSelection() {
        guard let folder, let plan else {
            selection = nil
            return
        }
        guard let validator = try? PlanValidator(scanner: FolderScanner(root: folder.url)) else {
            selection = nil
            error = "Butler could not read \(folder.path)."
            return
        }
        selection = PlanSelection(plan: plan, validator: validator)
    }
}

/// The index the applier last reported, written from its own thread.
private final class LastIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0

    var value: Int { lock.withLock { stored } }
    func set(_ index: Int) { lock.withLock { stored = index } }
}
