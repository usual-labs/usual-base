import BaseKit
import SwiftUI

/// The pane on the right: who changed the open file and when, from the Base's git history,
/// newest first.
struct HistoryPane: View {
    @Environment(BaseModel.self) private var base
    /// The pane stays alive while hidden; it reads history only while shown.
    let isShown: Bool
    /// Nil until loaded; `.some(nil)` when the Base isn't a git repository.
    @State private var changes: [FileChange]??
    @State private var problem: String?

    /// Changes whenever the history may have: another file, a sync, or the file changing on disk.
    private var refreshKey: String {
        [base.document?.relativePath ?? "", "\(base.sync.status)", "\(base.document?.loadCount ?? 0)", "\(isShown)"]
            .joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, 4)
        .task(id: refreshKey) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if base.document == nil {
            ContentUnavailableView("No File Selected", image: "lucide.clock")
        } else if let problem {
            ContentUnavailableView(
                "History Unavailable", image: "lucide.triangle-alert", description: Text(problem))
        } else if let changes {
            if let changes {
                if changes.isEmpty {
                    ContentUnavailableView(
                        "No Changes Yet", image: "lucide.clock",
                        description: Text("This file hasn’t been committed yet."))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(changes) { HistoryRow(change: $0) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .thinScrollers()
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No History", image: "lucide.clock")
                } description: {
                    Text("This Base isn’t a git repository. Sync keeps a history of every change.")
                } actions: {
                    Button("Set Up Sync…") { base.sync.isSetupShown = true }
                }
            }
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    private func load() async {
        guard isShown, let path = base.document?.relativePath else { return }
        do {
            let loaded = try await base.sync.history(of: path)
            guard path == base.document?.relativePath else { return }
            changes = .some(loaded)
            problem = nil
        } catch {
            problem = String(describing: error)
        }
    }
}

private struct HistoryRow: View {
    let change: FileChange

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image("lucide.circle-user-round")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(change.author.isEmpty ? "Unknown" : change.author)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(change.date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(change.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .help(
            "\(change.author) <\(change.email)>\n"
                + "\(change.date.formatted(date: .abbreviated, time: .shortened)) · \(change.id.prefix(10))")
    }
}
