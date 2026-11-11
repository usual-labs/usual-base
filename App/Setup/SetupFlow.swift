import AppKit
import BaseKit
import Observation

/// The wizard in the window's card that makes a new Base, or puts one the account has into a folder on this Mac.
/// It asks everything first (signing in, which Base, where its folder goes) and changes nothing until the person
/// confirms on the last step.
@MainActor @Observable
final class SetupFlow {
    enum Kind { case create, connect }
    enum Step { case signIn, name, pick, place, review, working }
    /// Where the Base's folder goes: the account's Bases folder, a new folder inside a project, or any folder.
    enum Place { case basesFolder, project, folder }

    let kind: Kind
    /// The steps, in order. Signing in is one only when the flow started signed out.
    let steps: [Step]
    var step: Step
    var name = ""
    var chosen: HostedBase?
    var place = Place.basesFolder
    var basesParent: URL?
    var project: URL?
    var subfolder = "base"
    var folder: URL?
    /// What's happening while it works, and why it stopped.
    var progress = ""
    var problem: String?
    /// The Base this flow created, so trying again after a problem doesn't create another.
    var created: HostedBase?

    init(kind: Kind, signedIn: Bool, basesParent: URL?) {
        self.kind = kind
        steps = (signedIn ? [] : [.signIn]) + [kind == .create ? .name : .pick, .place, .review]
        step = steps[0]
        self.basesParent = basesParent
    }

    var position: Int { steps.firstIndex(of: step) ?? steps.count - 1 }

    func next() {
        if position + 1 < steps.count { step = steps[position + 1] }
    }

    /// Back one step, past signing in once that's done.
    func back(signedIn: Bool) {
        guard let previous = steps[..<position].last(where: { $0 != .signIn || !signedIn }) else { return }
        step = previous
    }

    /// The Base on the server: the one this flow created, or the one chosen to connect.
    var existing: HostedBase? { created ?? (kind == .connect ? chosen : nil) }

    var baseName: String {
        kind == .create ? name.trimmingCharacters(in: .whitespacesAndNewlines) : chosen?.name ?? ""
    }

    // MARK: - Where the folder goes

    /// The folder the Base will be in, once the place has all it needs.
    func target(in account: AccountModel) -> URL? {
        switch place {
        case .basesFolder:
            guard let basesParent else { return nil }
            if let base = existing { return account.folder(for: base, in: basesParent) }
            let safe = baseName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            return basesParent.appending(path: safe, directoryHint: .isDirectory)
        case .project:
            guard let project, let path = cleanSubfolder else { return nil }
            return project.appending(path: path, directoryHint: .isDirectory)
        case .folder:
            return folder
        }
    }

    /// The folder inside the project, as a relative path, if it is one.
    private var cleanSubfolder: String? {
        let parts = subfolder.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty, !subfolder.hasPrefix("/"), parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { return nil }
        return parts.joined(separator: "/")
    }

    /// Why the place can't hold the Base, if it can't.
    func placeProblem(in account: AccountModel) -> String? {
        switch place {
        case .basesFolder:
            return nil
        case .project:
            guard project != nil else { return nil }
            guard let target = target(in: account) else {
                return "Type a folder name inside the project, such as “base” or “docs/notes”."
            }
            if Self.isRepository(target) || Self.hasFiles(target) {
                return "“\(subfolder)” already has files. Type a new folder name, or choose it under Another folder."
            }
            return nil
        case .folder:
            guard let folder, Self.isRepository(folder) else { return nil }
            let remote = (try? BaseRepository.open(folder))?.remoteURL
            return remote != nil && remote == existing?.git
                ? nil : "This folder is already a git repository of its own. Choose another folder."
        }
    }

    /// What happens to the folder, when that's worth saying.
    func placeNote(in account: AccountModel) -> String? {
        guard let target = target(in: account), placeProblem(in: account) == nil else { return nil }
        if Self.isRepository(target) { return "It’s there already, and opens as it is." }
        if place == .project, let project, Self.isRepository(project) {
            return "The project’s git ignores this folder, so the project’s commits leave the Base alone."
        }
        guard Self.hasFiles(target) else { return nil }
        if kind == .connect, chosen?.lastPushAt != nil {
            return "Its files and the Base’s notes are put together. Where a file differs, the folder’s version "
                + "is kept beside it as a conflict copy."
        }
        return "Its files become the Base’s first notes."
    }

    func canContinue(in account: AccountModel) -> Bool {
        switch step {
        case .signIn: account.state == .signedIn
        case .name: !baseName.isEmpty && baseName.count <= 80
        case .pick: chosen != nil
        // The Bases folder may still need choosing: Continue asks for it.
        case .place:
            (place == .basesFolder && basesParent == nil)
                || (target(in: account) != nil && placeProblem(in: account) == nil)
        case .review, .working: false
        }
    }

    static func isRepository(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: ".git").path(percentEncoded: false))
    }

    /// Whether the folder holds anything besides hidden files.
    static func hasFiles(_ folder: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.contains { !$0.hasPrefix(".") }
    }
}

extension BaseModel {
    func startSetup(_ kind: SetupFlow.Kind) {
        setup = SetupFlow(
            kind: kind, signedIn: account.state == .signedIn, basesParent: account.savedBasesFolder())
    }

    /// The last step: creates the Base if it's new, makes its folder, opens it and runs the first sync.
    func runSetup(_ flow: SetupFlow) async {
        flow.problem = nil
        flow.step = .working
        let hosted: HostedBase
        if let base = flow.existing {
            hosted = base
        } else {
            flow.progress = "Creating “\(flow.baseName)”…"
            do {
                hosted = try await account.createBase(named: flow.baseName)
                flow.created = hosted
            } catch {
                flow.problem = "Couldn’t create the Base: \(error)"
                flow.step = .review
                return
            }
        }
        guard let folder = flow.target(in: account) else {
            flow.step = .place
            return
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            flow.problem = "Couldn’t make the folder “\(folder.lastPathComponent)”: \(error.localizedDescription)"
            flow.step = .review
            return
        }
        EnclosingRepository.ignore(folder)
        let isClone = (try? BaseRepository.open(folder))?.remoteURL == hosted.git
        open(folder)
        rememberBookmark(for: folder)
        if !isClone {
            flow.progress = hosted.lastPushAt == nil ? "Setting up sync…" : "Downloading “\(hosted.name)”…"
            do {
                let address = try RemoteAddress(parsing: hosted.git)
                if let message = await sync.connect(to: address, credentials: nil, as: sync.identity) {
                    problem = "“\(hosted.name)” is open, but its first sync didn’t finish: \(message)"
                }
            } catch {
                problem = "“\(hosted.git)” isn’t a git address: \(error)"
            }
        }
        setup = nil
    }
}

#if DEBUG
    extension BaseModel {
        /// `USUALBASE_SETUP=create|connect[:name|pick|place|review|run]` opens the wizard at launch, at that step,
        /// for automated runs that can't click (`welcome` shows the card with no Base open). Later steps connect
        /// the Base named `USUALBASE_SETUP_BASE` (or the first listed) or create "Research", in a folder from
        /// `USUALBASE_SETUP_PROJECT` (a project: the Base goes into its `base` folder) or `USUALBASE_SETUP_FOLDER`.
        /// The sandbox only allows folders inside the app's container.
        func startDebugSetup(_ value: String) async {
            let parts = value.split(separator: ":").map(String.init)
            guard parts.first != "welcome" else { return }  // the card with no Base open
            startSetup(parts.first == "connect" ? .connect : .create)
            guard let flow = setup, parts.count > 1 else { return }
            let environment = ProcessInfo.processInfo.environment
            await account.refresh()
            flow.name = "Research"
            if flow.kind == .connect {
                let wanted = environment["USUALBASE_SETUP_BASE"]
                flow.chosen = account.bases.first { $0.name == wanted } ?? account.bases.first
            }
            if let path = environment["USUALBASE_SETUP_PROJECT"] {
                flow.place = .project
                flow.project = URL(filePath: path, directoryHint: .isDirectory)
            } else if let path = environment["USUALBASE_SETUP_FOLDER"] {
                flow.place = .folder
                flow.folder = URL(filePath: path, directoryHint: .isDirectory)
            }
            let steps: [String: SetupFlow.Step] = ["name": .name, "pick": .pick, "place": .place, "review": .review]
            if let step = steps[parts[1]] {
                flow.step = step
            } else if parts[1] == "run" {
                await runSetup(flow)
            }
        }
    }
#endif
