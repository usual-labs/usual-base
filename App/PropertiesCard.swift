import BaseKit
import SwiftUI

/// The front matter above the text: a title, a summary and the other properties. Edit opens
/// the raw YAML, so nothing in the file is reformatted unless you change it.
struct PropertiesCard: View {
    let frontMatter: FrontMatter
    let yaml: String
    let isReading: Bool
    let onSave: (String) -> Void

    @State private var draft: String?

    private static let headerKeys: Set<String> = ["title", "name", "description", "summary"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let draft {
                editor(draft)
            } else {
                header
                if let problem = frontMatter.problem {
                    Label(problem, image: "lucide.triangle-alert")
                        .foregroundStyle(.orange)
                }
                properties
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            if !isReading && draft == nil {
                Button("Edit") { draft = yaml }
                    .buttonStyle(.borderless)
                    .padding(10)
                    .help("Edit the properties as YAML")
            }
        }
    }

    @ViewBuilder private var header: some View {
        if let title = frontMatter.title {
            Text(title)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
        }
        if let summary = frontMatter.summary {
            Text(summary)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var rows: [FrontMatter.Property] {
        let shown = [frontMatter.title, frontMatter.summary]
        return frontMatter.properties.filter { property in
            guard Self.headerKeys.contains(property.key.lowercased()), case .text(let value) = property.value else {
                return true
            }
            return !shown.contains(value)
        }
    }

    @ViewBuilder private var properties: some View {
        if !rows.isEmpty {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(rows) { property in
                    GridRow {
                        Text(property.key)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        value(property.value)
                    }
                }
            }
            .font(.callout)
        }
    }

    @ViewBuilder private func value(_ value: FrontMatter.Property.Value) -> some View {
        switch value {
        case .text(let text):
            Text(text).textSelection(.enabled)
        case .list(let items):
            FlowLayout(spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.12), in: .capsule)
                }
            }
        case .date(let date):
            Text(Self.dateText(date))
                .help(date.formatted(.relative(presentation: .named)))
        case .link(let url):
            Link(url.absoluteString, destination: url)
        case .flag(let flag):
            Label(flag ? "Yes" : "No", image: flag ? "lucide.circle-check" : "lucide.circle")
        }
    }

    /// A YAML date without a time is midnight UTC; showing it in UTC keeps it on the right day.
    private static func dateText(_ date: Date) -> String {
        let isDateOnly = Int(date.timeIntervalSince1970) % 86_400 == 0
        var style = Date.FormatStyle(date: .abbreviated, time: isDateOnly ? .omitted : .shortened)
        if isDateOnly, let utc = TimeZone(identifier: "UTC") { style.timeZone = utc }
        return date.formatted(style)
    }

    private func editor(_ text: String) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextEditor(text: Binding(get: { draft ?? text }, set: { draft = $0 }))
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 90, maxHeight: 320)
            HStack {
                Button("Cancel") { draft = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Done") {
                    if let draft, draft != yaml { onSave(draft) }
                    draft = nil
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }
}

/// Lays chips out in rows, wrapping when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width && !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
