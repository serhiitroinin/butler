import ButlerCore
import SwiftUI

struct RulesInspector: View {
    @ObservedObject var page: FolderViewModel
    let selected: PlanTableNode?

    var body: some View {
        Form {
            if let selected, !selected.reason.isEmpty {
                Section("Why") {
                    Text(selected.reason)
                        .font(.callout)
                }
            }
            if let plan = page.plan, !plan.summary.isEmpty {
                Section("Notes") {
                    Text(plan.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if !page.failures.isEmpty {
                Section("Problems") {
                    ForEach(page.failures) { line in
                        DisclosureGroup {
                            Text(line.detail ?? "")
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        } label: {
                            Label(line.text, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Stock.red)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onPaper()
    }
}

struct RuleTemplate: Identifiable {
    let id = UUID()
    let title: String
    let text: String

    static let all: [RuleTemplate] = [
        RuleTemplate(title: "Downloads", text: """
            Sort my Downloads folder.
            Put invoices and statements in Invoices/<year>.
            Put screenshots in Screenshots/<year>.
            Put installers (.dmg, .pkg) in Installers.
            Put archives (.zip, .tar.gz) in Archives.
            Leave anything from the last seven days where it is.
            """),
        RuleTemplate(title: "Documents", text: """
            Sort my Documents folder by subject, not by file type.
            Use the folders Finance, Health, Home, Travel, and Work.
            Add a year folder under Finance.
            Rename a file when its name does not say what it is.
            """),
        RuleTemplate(title: "Screenshots", text: """
            Group screenshots by month in the form YYYY-MM.
            Keep the original file names.
            Move anything that is not a screenshot into Other.
            """),
        RuleTemplate(title: "Project archive", text: """
            This folder holds finished project files.
            Make one folder per project and name it after the client.
            Put the newest version of a document at the top of its project folder.
            Put older versions in an Older folder inside the project.
            """),
    ]
}
