import ButlerCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            EngineSettings()
                .tabItem { Label("Engines", systemImage: "cpu") }
        }
        .frame(width: 520, height: 380)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var model: AppModel
    @State private var rules = ""

    var body: some View {
        Form {
            Section("Default engine") {
                Picker("Engine", selection: engineBinding) {
                    ForEach(model.service.engines, id: \.id) { engine in
                        Text(engine.label).tag(engine.id)
                    }
                }
                if let catalog = selectedCatalog {
                    Picker("Model", selection: modelBinding(catalog)) {
                        ForEach(catalog.models) { value in
                            Text(value.label).tag(value.id)
                        }
                    }
                }
            }
            Section("Default rules") {
                TextEditor(text: $rules)
                    .font(.body)
                    .frame(minHeight: 120)
                    .onChange(of: rules) { _, value in model.store.settings.defaultRules = value }
                Text("Butler copies these into every folder you add.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { rules = model.store.settings.defaultRules }
    }

    private var selectedCatalog: EngineCatalog? {
        model.service.engine(model.store.settings.choice.engineId ?? model.service.defaultEngineId)?.catalog.value
    }

    private var engineBinding: Binding<String> {
        Binding(
            get: { model.store.settings.choice.engineId ?? model.service.defaultEngineId ?? "" },
            set: { id in
                var value = EngineChoice(engineId: id)
                let catalog = model.service.engine(id)?.catalog.value
                value.modelId = catalog?.defaultModelId ?? catalog?.models.first?.id
                model.store.settings.choice = value
            }
        )
    }

    private func modelBinding(_ catalog: EngineCatalog) -> Binding<String> {
        Binding(
            get: { model.store.settings.choice.modelId ?? catalog.defaultModelId ?? "" },
            set: { model.store.settings.choice.modelId = $0 }
        )
    }
}

private struct EngineSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Butler needs these to run an engine") {
                ToolRow(name: "Node.js", path: model.service.environment.node, required: true, fix: "brew install node")
                ToolRow(
                    name: "Claude Code",
                    path: model.service.environment.claude,
                    required: false,
                    fix: "npm install -g @anthropic-ai/claude-code"
                )
                ToolRow(
                    name: "Codex",
                    path: model.service.environment.codex,
                    required: false,
                    fix: "npm install -g @openai/codex"
                )
            }
            Section {
                LabeledContent("Status", value: status)
                Button("Check Again") { Task { await model.service.refresh() } }
            }
        }
        .formStyle(.grouped)
    }

    private var status: String {
        switch model.service.status {
        case .idle: return "Not connected"
        case .starting: return "Starting"
        case .ready: return model.service.offline ? "Offline engine" : "Ready"
        case let .failed(message): return message
        }
    }
}

private struct ToolRow: View {
    let name: String
    let path: String?
    let required: Bool
    let fix: String

    var body: some View {
        LabeledContent {
            if let path {
                Text(path)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            } else {
                HStack(spacing: 6) {
                    Text(fix)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(fix, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }
        } label: {
            Label {
                Text(name)
            } icon: {
                Image(systemName: path == nil ? "xmark.circle" : "checkmark.circle.fill")
                    .foregroundStyle(path == nil ? (required ? Color.red : .secondary) : .green)
            }
        }
    }
}
