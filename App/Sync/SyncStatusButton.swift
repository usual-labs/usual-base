import BaseKit
import SwiftUI

/// The toolbar's sync button. It shows how syncing is going and opens the details.
struct SyncStatusButton: View {
    @Environment(BaseModel.self) private var base
    @State private var isDetailShown = false

    var body: some View {
        let status = base.sync.status
        Button {
            if status == .off { base.sync.isSetupShown = true } else { isDetailShown.toggle() }
        } label: {
            Label(status.title, image: status.symbol)
                .symbolEffect(.rotate, isActive: status == .syncing)
        }
        .help(status == .off ? "Sync this Base with a git repository" : status.title)
        .disabled(base.root == nil)
        .popover(isPresented: $isDetailShown, arrowEdge: .bottom) {
            SyncDetailView { isDetailShown = false }
        }
    }
}

private struct SyncDetailView: View {
    @Environment(BaseModel.self) private var base
    let close: () -> Void

    var body: some View {
        let sync = base.sync
        VStack(alignment: .leading, spacing: 8) {
            Text(sync.status.headline)
                .font(.headline)
            if let detail = sync.status.detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let remote = sync.remoteURL {
                Text(remote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            if !sync.conflicts.isEmpty {
                Divider()
                Text("Kept both versions")
                    .font(.subheadline.bold())
                Text(
                    "Each file changed here and elsewhere at once. The other version kept the name; this Mac’s is the copy."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                ForEach(sync.conflicts.prefix(5), id: \.copy) { conflict in
                    Button(conflict.copy) {
                        close()
                        base.openFile(conflict.copy)
                    }
                    .buttonStyle(.link)
                }
            }
            Divider()
            HStack {
                Button("Settings…") {
                    close()
                    sync.isSetupShown = true
                }
                Spacer()
                Button("Sync Now") { sync.syncNow() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sync.status == .syncing)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}

extension SyncController.Status {
    var title: String {
        switch self {
        case .off: "Set Up Sync"
        case .syncing: "Syncing"
        case .synced: "Synced"
        case .offline: "Offline"
        case .needsCredentials: "Sync Paused"
        case .failed: "Sync Failed"
        }
    }

    var symbol: String {
        switch self {
        case .off, .syncing: "lucide.refresh-cw"
        case .synced: "lucide.circle-check"
        case .offline: "lucide.wifi-off"
        case .needsCredentials: "lucide.key-round"
        case .failed: "lucide.triangle-alert"
        }
    }

    var headline: String {
        switch self {
        case .off: "Not syncing"
        case .syncing: "Syncing…"
        case .synced(let date): "Synced \(date.formatted(.relative(presentation: .named)))"
        case .offline: "Can’t reach the repository"
        case .needsCredentials: "The repository didn’t accept the token"
        case .failed: "Sync failed"
        }
    }

    var detail: String? {
        switch self {
        case .offline(let message): "Usual Base tries again every minute. \(message)"
        case .needsCredentials: "Syncing is paused. Open Settings and paste a new token."
        case .failed(let message): message
        default: nil
        }
    }
}
