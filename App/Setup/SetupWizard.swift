import AppKit
import SwiftUI

/// The setup wizard in the window's card (`SetupFlow`): one question per step, with a way back, and nothing done
/// until the last step.
struct SetupWizard: View {
    @Environment(BaseModel.self) private var base
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let flow: SetupFlow
    @State private var forward = true
    @FocusState private var nameFocused: Bool

    var body: some View {
        let account = base.account
        VStack(spacing: 0) {
            HStack {
                Spacer()
                StepDots(count: flow.steps.count, position: flow.position)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                if flow.step != .working {
                    Button("Cancel") { cancel() }
                        .buttonStyle(.borderless)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heading
                    content
                }
                .frame(maxWidth: 480, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
                .id(flow.step)
                .transition(stepTransition)
            }
            .scrollBounceBehavior(.basedOnSize)
            if flow.step != .working {
                HStack {
                    if flow.position > 0 {
                        Button("Back") { go(forward: false) { flow.back(signedIn: account.state == .signedIn) } }
                    }
                    Spacer()
                    Button(primaryTitle) { proceed() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(flow.step != .review && !flow.canContinue(in: account))
                }
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .animation(.smooth(duration: 0.32), value: flow.step)
        .onChange(of: account.state) { _, state in
            if state == .signedIn, flow.step == .signIn { go(forward: true) { flow.next() } }
        }
    }

    // MARK: - Steps

    private var heading: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = stepImage {
                Image(image)
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(.primary.opacity(0.06), in: .rect(cornerRadius: 11))
            }
            Text(stepTitle).font(.system(size: 22, weight: .semibold))
            if let subtitle = stepSubtitle {
                Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var content: some View {
        @Bindable var flow = flow
        let account = base.account
        switch flow.step {
        case .signIn:
            signIn
        case .name:
            TextField("Research notes", text: $flow.name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused($nameFocused)
                .onAppear { nameFocused = true }
                .onSubmit { if flow.canContinue(in: account) { proceed() } }
        case .pick:
            BasePicker(flow: flow)
        case .place:
            PlacePicker(flow: flow)
        case .review:
            review
        case .working:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(flow.progress).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var signIn: some View {
        let account = base.account
        switch account.state {
        case .signingIn(let code, let url):
            VStack(alignment: .leading, spacing: 12) {
                Text("Check that the page in your browser shows this code:").foregroundStyle(.secondary)
                Text(code)
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for you to approve it…").foregroundStyle(.secondary)
                }
                Button("Open the Browser Again") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.link)
            }
        case .signedIn:
            Label("Signed in", image: "lucide.circle-check")
        case .signedOut:
            Button("Sign In with Your Browser") { account.signIn() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var review: some View {
        let account = base.account
        let target = flow.target(in: account).map(tildePath) ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            if flow.kind == .create {
                SummaryRow(
                    image: "lucide.cloud",
                    text:
                        "Creates “\(flow.baseName)” in your Usual Base account, on \(account.api.server.host() ?? "")."
                )
            }
            SummaryRow(image: "lucide.folder", text: "Keeps it in \(target).")
            if let note = flow.placeNote(in: account) {
                SummaryRow(image: flow.place == .project ? "lucide.code-xml" : "lucide.file-text", text: note)
            }
            SummaryRow(
                image: "lucide.refresh-cw", text: "Syncs it, so your agents and your other Macs get each change.")
            if let problem = flow.problem {
                Label(problem, image: "lucide.triangle-alert")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var stepImage: String? {
        switch flow.step {
        case .signIn: "lucide.key-round"
        case .name: "lucide.library"
        case .pick: "lucide.link"
        case .place: "lucide.folder"
        case .review: "lucide.circle-check"
        case .working: nil
        }
    }

    private var stepTitle: String {
        let name = flow.baseName
        switch flow.step {
        case .signIn: return "Sign in to Usual Base"
        case .name: return "Name your new Base"
        case .pick: return "Which Base?"
        case .place: return "Where should “\(name)” live?"
        case .review: return flow.kind == .create ? "Ready to create “\(name)”" : "Ready to connect “\(name)”"
        case .working: return flow.kind == .create ? "Creating “\(name)”" : "Connecting “\(name)”"
        }
    }

    private var stepSubtitle: String? {
        switch flow.step {
        case .signIn:
            "Your Bases are kept in your Usual Base account, so agents on other machines share them too. "
                + "This Mac signs in once, in your browser."
        case .name: "Name it after what it holds: a project, a team or a topic. You can rename it later."
        case .pick: "Choose the Base to put in a folder on this Mac."
        case .place:
            "A Base is a folder of plain Markdown files on this Mac, kept in sync. Agents read and write it there."
        case .review: "Nothing has changed yet."
        case .working: nil
        }
    }

    private var primaryTitle: String {
        guard flow.step == .review else { return "Continue" }
        return flow.kind == .create ? "Create Base" : "Connect Base"
    }

    // MARK: - Moving between steps

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(x: forward ? 36 : -36).combined(with: .opacity),
            removal: .offset(x: forward ? -36 : 36).combined(with: .opacity))
    }

    private func go(forward: Bool, _ change: () -> Void) {
        self.forward = forward
        withAnimation(.smooth(duration: 0.32)) { change() }
    }

    private func proceed() {
        let account = base.account
        switch flow.step {
        case .review:
            forward = true
            Task { await base.runSetup(flow) }
        case .place where flow.place == .basesFolder && flow.basesParent == nil:
            // The Bases folder is chosen once, when it's first needed.
            guard let parent = account.basesFolder() else { return }
            flow.basesParent = parent
            if flow.placeProblem(in: account) == nil { go(forward: true) { flow.next() } }
        default:
            guard flow.canContinue(in: account) else { return }
            go(forward: true) { flow.next() }
        }
    }

    private func cancel() {
        if case .signingIn = base.account.state { base.account.cancelSignIn() }
        withAnimation(.smooth(duration: 0.3)) { base.setup = nil }
    }
}

/// Where a step is in the wizard: a dot per step, the current one wider.
private struct StepDots: View {
    let count: Int
    let position: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(.primary.opacity(index <= position ? 0.75 : 0.15))
                    .frame(width: index == position ? 18 : 6, height: 6)
            }
        }
        .animation(.smooth(duration: 0.3), value: position)
        .accessibilityElement()
        .accessibilityLabel("Step \(position + 1) of \(count)")
    }
}

struct SummaryRow: View {
    let image: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(image).foregroundStyle(.secondary).frame(width: 18)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A path to show, with the home folder as ~ (the sandbox's own home is the app's container, not the person's).
func tildePath(_ url: URL) -> String {
    var path = url.path(percentEncoded: false)
    if path.count > 1, path.hasSuffix("/") { path.removeLast() }
    guard let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir.map({ String(cString: $0) }) else {
        return path
    }
    return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
}
