import ButlerCore
import SwiftUI

/// A standard pull-down menu. Everything in it comes from sidecar discovery.
struct EngineMenu: View {
    @ObservedObject var page: FolderViewModel
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Menu {
            Picker("Engine", selection: engineBinding) {
                ForEach(model.service.engines, id: \.id) { engine in
                    Text(engine.label).tag(engine.id)
                }
            }
            .pickerStyle(.inline)
            if let engine = selectedEngine {
                Divider()
                switch engine.catalog {
                case let .available(catalog):
                    Picker("Model", selection: modelBinding(catalog)) {
                        ForEach(catalog.models) { model in
                            Text(model.label).tag(model.id)
                        }
                    }
                    .pickerStyle(.inline)
                    if let model = selectedModel(in: catalog), !model.efforts.isEmpty {
                        Divider()
                        Picker("Effort", selection: effortBinding(model)) {
                            if model.defaultEffortId == nil {
                                /// The catalog names no default, so none is claimed:
                                /// the run sends no effort and the engine decides.
                                Text("Default").tag("")
                            }
                            ForEach(model.efforts) { option in
                                Text(option.label).tag(option.id)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                case let .unavailable(message):
                    Button(message) {}.disabled(true)
                case let .unsupported(message):
                    Button(message ?? "This engine publishes no models.") {}.disabled(true)
                }
                ForEach(controls(of: engine)) { control in
                    if case let .select(options, defaultValue) = control.kind {
                        Divider()
                        Picker(control.label, selection: controlBinding(control.id, options, defaultValue)) {
                            ForEach(options) { option in
                                Text(option.label).tag(option.id)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }
                Divider()
                ForEach(limits(of: engine), id: \.self) { line in
                    Button(line) {}.disabled(true)
                }
            }
        } label: {
            Text(title)
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Choose the engine and the model for this folder")
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            /// A pull-down menu has no "will open"; any menu starting to track
            /// asks again, and the service drops calls that come too close.
            let id = selectedEngine?.id
            Task { await model.service.refresh(engine: id) }
        }
    }

    private var choice: EngineChoice {
        let folder = page.folder?.choice ?? EngineChoice()
        return folder.isEmpty ? model.store.settings.choice : folder
    }

    private var selectedEngine: Engine? {
        model.service.engine(choice.engineId ?? model.service.defaultEngineId)
    }

    private var title: String {
        guard let engine = selectedEngine else { return "No Engine" }
        guard let catalog = engine.catalog.value else { return engine.label }
        let id = choice.modelId ?? catalog.defaultModelId ?? catalog.models.first?.id
        let name = catalog.models.first { $0.id == id }?.label ?? id
        return name.map { "\(engine.label) · \($0)" } ?? engine.label
    }

    private func controls(of engine: Engine) -> [ButlerCore.EngineControl] {
        let model = engine.catalog.value?.models.first { $0.id == choice.modelId }
        var merged = engine.controls
        for control in model?.controls ?? [] where !merged.contains(where: { $0.id == control.id }) {
            merged.append(control)
        }
        return merged
    }

    /// The model the run will use: the chosen one, or the catalog's default.
    private func selectedModel(in catalog: EngineCatalog) -> EngineModel? {
        let id = choice.modelId ?? catalog.defaultModelId ?? catalog.models.first?.id
        return catalog.models.first { $0.id == id }
    }

    /// `Max plan`, then one line per window: `5-hour · 82% left · resets in 3 hours`.
    private func limits(of engine: Engine) -> [String] {
        switch engine.limits {
        case let .available(value):
            var lines = value.planLabel.map { ["\($0) plan"] } ?? []
            for line in value.lines {
                var parts = [line.label]
                if let percent = line.usedPercent {
                    parts.append("\(max(0, Int(100 - percent)))% left")
                } else if let used = line.used, let limit = line.limit {
                    parts.append("\(used.formatted()) of \(limit.formatted()) \(line.unit)")
                } else {
                    continue
                }
                if let resets = line.resetsAt, resets > Date() {
                    parts.append("resets \(RelativeDateTimeFormatter().localizedString(for: resets, relativeTo: Date()))")
                }
                lines.append(parts.joined(separator: " · "))
            }
            return lines.isEmpty ? ["No limits reported"] : lines
        case let .unavailable(message): return [message]
        case .unsupported: return ["No account limits reported"]
        }
    }

    private var engineBinding: Binding<String> {
        Binding(
            get: { choice.engineId ?? model.service.defaultEngineId ?? "" },
            set: { id in
                var value = EngineChoice(engineId: id)
                let catalog = model.service.engine(id)?.catalog.value
                value.modelId = catalog?.defaultModelId ?? catalog?.models.first?.id
                page.updateChoice(value)
            }
        )
    }

    private func modelBinding(_ catalog: EngineCatalog) -> Binding<String> {
        Binding(
            get: { choice.modelId ?? catalog.defaultModelId ?? catalog.models.first?.id ?? "" },
            set: { id in
                var value = choice
                value.modelId = id
                value.effortId = nil
                page.updateChoice(value)
            }
        )
    }

    private func effortBinding(_ engineModel: EngineModel) -> Binding<String> {
        Binding(
            get: { choice.effortId ?? engineModel.defaultEffortId ?? "" },
            set: { id in
                var value = choice
                value.effortId = id.isEmpty ? nil : id
                page.updateChoice(value)
            }
        )
    }

    private func controlBinding(
        _ id: String,
        _ options: [EngineOption],
        _ fallback: String?
    ) -> Binding<String> {
        Binding(
            get: {
                if case let .text(value) = choice.controls[id] { return value }
                return fallback ?? options.first?.id ?? ""
            },
            set: { value in
                var next = choice
                next.controls[id] = .text(value)
                page.updateChoice(next)
            }
        )
    }
}
