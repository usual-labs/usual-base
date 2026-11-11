import AppKit
import SwiftUI

/// The account's Bases, one to choose.
struct BasePicker: View {
    @Environment(BaseModel.self) private var base
    let flow: SetupFlow

    var body: some View {
        let account = base.account
        Group {
            if account.bases.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("You don’t have a Base yet.").foregroundStyle(.secondary)
                    Button("Create a Base Instead") { base.startSetup(.create) }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(account.bases) { hosted in
                        Button {
                            flow.chosen = hosted
                        } label: {
                            HStack(spacing: 12) {
                                Image("lucide.library").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hosted.name).font(.headline)
                                    Text(detail(hosted)).font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if flow.chosen == hosted { Image("lucide.circle-check") }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(.rect(cornerRadius: 14))
                        }
                        .buttonStyle(ChoiceCardStyle(isSelected: flow.chosen == hosted))
                    }
                }
            }
        }
        .task { await account.refresh() }
    }

    private func detail(_ hosted: HostedBase) -> String {
        guard let pushed = hosted.lastPushAt else { return "No notes yet" }
        let date = Date(timeIntervalSince1970: pushed / 1000)
        return "Changed " + date.formatted(.relative(presentation: .named))
    }
}

/// Where the Base's folder goes: the Bases folder, a new folder inside a project, or any folder.
struct PlacePicker: View {
    @Environment(BaseModel.self) private var base
    let flow: SetupFlow

    var body: some View {
        @Bindable var flow = flow
        let account = base.account
        VStack(alignment: .leading, spacing: 8) {
            option(
                .basesFolder, image: "lucide.library", title: "Your Bases folder",
                text: flow.basesParent == nil
                    ? "A folder you choose once, such as ~/Usual Base, where this Mac keeps your Bases."
                    : "In \(flow.target(in: account).map(tildePath) ?? ""), with your other Bases.")
            option(
                .project, image: "lucide.code-xml", title: "Inside a project",
                text: "Agents working in the project, such as Claude Code, read and edit the Base like the "
                    + "project’s own files.")
            if flow.place == .project, let project = flow.project {
                HStack(spacing: 6) {
                    Text(tildePath(project) + "/")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    TextField("base", text: $flow.subfolder)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                    Button("Change…") { chooseProject() }
                }
                .padding(.leading, 16)
            }
            option(
                .folder, image: "lucide.folder", title: "Another folder",
                text: flow.folder.map { "In \(tildePath($0))." }
                    ?? "An empty folder, a new one, or a folder of notes to start the Base with.")
            if flow.place == .folder, flow.folder != nil {
                Button("Choose Another Folder…") { chooseFolder() }
                    .buttonStyle(.link)
                    .padding(.leading, 16)
            }
            if let problem = flow.placeProblem(in: account) {
                Label(problem, image: "lucide.triangle-alert")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } else if let note = flow.placeNote(in: account) {
                Text(note)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .animation(.smooth(duration: 0.25), value: flow.place)
    }

    private func option(_ place: SetupFlow.Place, image: String, title: String, text: String) -> some View {
        Button {
            flow.place = place
            // Choosing a project or folder is part of picking the option, the first time.
            if place == .project, flow.project == nil { chooseProject() }
            if place == .folder, flow.folder == nil { chooseFolder() }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(image)
                    .font(.system(size: 16))
                    .frame(width: 30, height: 30)
                    .background(.primary.opacity(0.06), in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(ChoiceCardStyle(isSelected: flow.place == place))
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose Project"
        panel.message =
            "Choose the project’s folder, the one with its git repository. The Base goes into a new folder inside it."
        if panel.runModal() == .OK, let url = panel.url { flow.project = url }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose a folder for the Base: an empty one, a new one, or a folder of notes."
        if panel.runModal() == .OK, let url = panel.url { flow.folder = url }
    }
}
