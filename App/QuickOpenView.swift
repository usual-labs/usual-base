import BaseKit
import SwiftUI

/// ⌘P: type part of a file's name or path, then Return.
struct QuickOpenView: View {
    @Environment(BaseModel.self) private var base
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var highlighted = 0

    private var results: [String] { BaseIndex.rank(query, in: base.paths, limit: 60) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Find a file", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(14)
                .onSubmit { open(at: highlighted) }
                .onKeyPress(.downArrow) {
                    highlighted = min(highlighted + 1, max(results.count - 1, 0))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    highlighted = max(highlighted - 1, 0)
                    return .handled
                }
                .onChange(of: query) { highlighted = 0 }
            Divider()
            ScrollViewReader { proxy in
                List(Array(results.enumerated()), id: \.element) { index, path in
                    row(path, isHighlighted: index == highlighted)
                        .id(index)
                        .contentShape(.rect)
                        .onTapGesture { open(at: index) }
                }
                .listStyle(.plain)
                .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
            }
            if results.isEmpty {
                Text(base.paths.isEmpty ? "This Base has no files yet." : "No file matches “\(query)”.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .frame(width: 560, height: 380)
        .onExitCommand { dismiss() }
    }

    private func row(_ path: String, isHighlighted: Bool) -> some View {
        let url = URL(filePath: path)
        let folder = url.deletingLastPathComponent().relativePath
        return HStack(spacing: 8) {
            Image(FileIcons.file(path))
                .foregroundStyle(.secondary)
            Text(BaseIndex.isMarkdown(path) ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent)
            if folder != "." {
                Text(folder)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(isHighlighted ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 6))
    }

    private func open(at index: Int) {
        guard results.indices.contains(index) else { return }
        base.openFile(results[index])
        dismiss()
    }
}
