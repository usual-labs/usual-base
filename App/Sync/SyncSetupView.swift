import BaseKit
import SwiftUI

/// Connects the open Base to a git repository, or changes how it syncs.
struct SyncSetupView: View {
    @Environment(BaseModel.self) private var base
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var username = ""
    @State private var token = ""
    @State private var name = ""
    @State private var email = ""
    @State private var hasSavedToken = false
    @State private var isWorking = false
    @State private var message: String?

    private var isSetUp: Bool { base.sync.status != .off }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Repository", text: $address, prompt: Text("https://github.com/you/notes.git"))
                    SecureField(
                        "Token", text: $token,
                        prompt: Text(hasSavedToken ? "Saved in your keychain" : "A token that can push"))
                    TextField("User name", text: $username, prompt: Text("Only if your host asks for one"))
                } header: {
                    Text("Sync “\(base.name ?? "this Base")” with a git repository")
                } footer: {
                    Text(
                        "Usual Base commits every change in this folder and keeps it in step with the repository, so agents that clone it see the same files."
                    )
                }
                Section("Author of this Mac’s commits") {
                    TextField("Name", text: $name)
                    TextField("Email", text: $email)
                }
                if let message {
                    Text(message)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .disabled(isWorking)
            HStack {
                if isSetUp {
                    Button("Stop Syncing", role: .destructive) {
                        Task {
                            await base.sync.stopSyncing()
                            dismiss()
                        }
                    }
                }
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isSetUp ? "Save" : "Start Syncing") { Task { await connect() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || address.isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 500)
        .onAppear(perform: fill)
    }

    private func fill() {
        address = base.sync.remoteURL ?? ""
        if let saved = base.sync.remoteURL.flatMap(base.sync.savedCredentials(for:)) {
            username = saved.username == "x-access-token" ? "" : saved.username
            hasSavedToken = true
        }
        let identity = base.sync.identity
        name = identity.name
        email = identity.email
    }

    private func connect() async {
        message = nil
        let parsed: RemoteAddress
        do {
            parsed = try RemoteAddress(parsing: address)
        } catch {
            message = error.description
            return
        }
        let identity = GitIdentity(
            name: name.trimmingCharacters(in: .whitespaces), email: email.trimmingCharacters(in: .whitespaces))
        guard !identity.name.isEmpty, !identity.email.isEmpty else {
            message = "Enter the name and email your commits should carry."
            return
        }
        let typedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let typedUser = username.trimmingCharacters(in: .whitespaces)
        let credentials =
            parsed.credentials
            ?? (typedToken.isEmpty
                ? nil : GitCredentials(username: typedUser.isEmpty ? "x-access-token" : typedUser, token: typedToken))
        isWorking = true
        message = await base.sync.connect(to: parsed, credentials: credentials, as: identity)
        isWorking = false
        if message == nil { dismiss() }
    }
}
