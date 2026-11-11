import AppKit
import BaseKit
import SwiftUI

extension BaseModel {
    /// Opens a hosted Base, cloning it into the Bases folder the first time.
    func openHosted(_ hosted: HostedBase) async {
        guard let parent = account.basesFolder() else { return }
        let folder = account.folder(for: hosted, in: parent)
        let isClone = FileManager.default.fileExists(atPath: folder.appending(path: ".git").path(percentEncoded: false))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            problem = "Couldn’t create “\(folder.lastPathComponent)”: \(error.localizedDescription)"
            return
        }
        open(folder)
        rememberBookmark(for: folder)
        guard !isClone else { return }
        do {
            let address = try RemoteAddress(parsing: hosted.git)
            if let message = await sync.connect(to: address, credentials: nil, as: sync.identity) {
                problem = "Couldn’t download “\(hosted.name)”: \(message)"
            }
        } catch {
            problem = "“\(hosted.git)” isn’t a git address: \(error)"
        }
    }

    /// Watches the open Base's room for pushes when it's a hosted Base, and stops watching otherwise.
    func remoteChanged(_ remoteURL: String?) {
        live?.stop()
        live = nil
        sync.hasLiveUpdates = false
        guard let remoteURL else { return }
        live = account.liveUpdates(
            for: remoteURL,
            onPush: { [weak self] in self?.sync.remoteChanged() },
            onConnected: { [weak self] connected in self?.sync.hasLiveUpdates = connected })
    }
}

/// The menu at the top of the sidebar: the open Base's name, the account's other Bases, and signing in.
struct BaseSwitcher: View {
    @Environment(BaseModel.self) private var base

    var body: some View {
        let account = base.account
        Menu {
            if account.state == .signedIn {
                Section("Your Bases") {
                    ForEach(account.bases) { hosted in
                        Button(hosted.name) { Task { await base.openHosted(hosted) } }
                    }
                    if account.bases.isEmpty {
                        Text("No Bases yet")
                    }
                }
                Button("Refresh List") { Task { await account.refresh() } }
                Divider()
            }
            Button("New Base…") { base.startSetup(.create) }
            Button("Connect a Base to a Folder…") { base.startSetup(.connect) }
            Button("Open Folder…") { base.chooseBase() }
            Divider()
            switch account.state {
            case .signedIn:
                Button("Manage Account…") { NSWorkspace.shared.open(account.api.server) }
                Button("Sign Out\(account.email.map { " (\($0))" } ?? "")") { account.signOut() }
            case .signingIn:
                Button("Cancel Signing In") { account.cancelSignIn() }
            case .signedOut:
                Button("Sign In to Usual Base…") { account.signIn() }
            }
        } label: {
            HStack(spacing: 4) {
                Text(base.name ?? "Usual Base").font(.headline).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .task { if account.state == .signedIn { await account.refresh() } }
    }
}

/// While signing in: the code to check in the browser.
struct SignInSheet: View {
    let account: AccountModel
    let code: String
    let url: URL

    var body: some View {
        VStack(spacing: 16) {
            Text("Approve this Mac in your browser").font(.title3.weight(.semibold))
            Text("Check that the page shows this code:").foregroundStyle(.secondary)
            Text(code).font(.system(size: 30, weight: .semibold, design: .monospaced)).textSelection(.enabled)
            HStack {
                Button("Cancel") { account.cancelSignIn() }
                    .keyboardShortcut(.cancelAction)
                Button("Open Browser Again") { NSWorkspace.shared.open(url) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(minWidth: 360)
    }
}
