import AppKit
import Markdown

extension Renderer {
    /// A text table with one paragraph per cell. Its columns are sized by their text, since
    /// AppKit's automatic table layout gives every column the same width.
    mutating func table(_ table: Table, in context: Context) {
        flushMarker(in: context)
        let columns = max(table.maxColumnCount, 1)
        let headerFont = style.bodyFont.adding(.bold)
        let rows = [Array(table.head.cells)] + table.body.rows.map { Array($0.cells) }
        let contents: [[NSAttributedString]] = rows.enumerated().map { row, cells in
            (0..<columns).map { column in
                guard column < cells.count else { return NSAttributedString() }
                return inlines(cells[column], font: row == 0 ? headerFont : style.bodyFont, color: context.color)
            }
        }
        let widths = columnWidths(contents, available: style.textWidth - context.indent)

        let grid = NSTextTable()
        grid.numberOfColumns = columns
        grid.collapsesBorders = true
        grid.hidesEmptyCells = false
        grid.setContentWidth(widths.table, type: .percentageValueType)
        grid.setWidth(space(10), type: .absoluteValueType, for: .margin, edge: .minY)
        grid.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
        for (row, cells) in contents.enumerated() {
            for (column, content) in cells.enumerated() {
                let cell = NSTextTableBlock(
                    table: grid, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                cell.setContentWidth(widths.columns[column], type: .percentageValueType)
                cell.setWidth(1, type: .absoluteValueType, for: .border)
                cell.setBorderColor(.separatorColor)
                cell.setWidth(5, type: .absoluteValueType, for: .padding)
                cell.setWidth(Self.cellSidePadding, type: .absoluteValueType, for: .padding, edge: .minX)
                cell.setWidth(Self.cellSidePadding, type: .absoluteValueType, for: .padding, edge: .maxX)
                if row == 0 { cell.backgroundColor = .quaternarySystemFill }
                var inner = context
                inner.blocks.append(cell)
                inner.indent = 0
                let alignment = column < table.columnAlignments.count ? table.columnAlignments[column] : nil
                write(
                    content, in: inner, spacing: 0, alignment: Self.textAlignment(alignment),
                    font: row == 0 ? headerFont : style.bodyFont)
            }
        }
    }

    private static let cellSidePadding: CGFloat = 10

    /// Shares the width out the way a browser does: each column gets at least its longest word,
    /// and the rest goes to the columns with the most text. Returns each column's share of the
    /// table and the table's share of the text width, both in percent.
    func columnWidths(_ contents: [[NSAttributedString]], available: CGFloat) -> (table: CGFloat, columns: [CGFloat]) {
        let chrome = 2 * Self.cellSidePadding + 1
        let count = contents.first?.count ?? 0
        var least = [CGFloat](repeating: chrome, count: count)
        var most = least
        for row in contents {
            for (column, content) in row.enumerated() {
                most[column] = max(most[column], ceil(content.size().width) + chrome)
                least[column] = max(least[column], min(longestWord(in: content), 200) + chrome)
            }
        }
        let widths: [CGFloat]
        let spare = available - least.reduce(0, +)
        let wanted = zip(most, least).map { $0 - $1 }.reduce(0, +)
        if most.reduce(0, +) <= available || wanted <= 0 {
            widths = most
        } else if spare <= 0 {
            widths = least
        } else {
            widths = zip(most, least).map { most, least in least + spare * (most - least) / wanted }
        }
        let total = max(widths.reduce(0, +), 1)
        return (min(100, total / max(available, 1) * 100), widths.map { $0 / total * 100 })
    }

    /// The width of the longest run of text without a space in it. Only the run with the most
    /// characters is measured, since measuring every word is slow.
    private func longestWord(in content: NSAttributedString) -> CGFloat {
        let text = content.string as NSString
        var longest = NSRange(location: 0, length: 0)
        var start = 0
        for offset in 0...text.length {
            let isBreak =
                offset == text.length
                || CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(text.character(at: offset)) ?? " ")
            guard isBreak else { continue }
            if offset - start > longest.length { longest = NSRange(location: start, length: offset - start) }
            start = offset + 1
        }
        return longest.length > 0 ? ceil(content.attributedSubstring(from: longest).size().width) : 0
    }

    private static func textAlignment(_ alignment: Table.ColumnAlignment?) -> NSTextAlignment {
        switch alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        case nil: .natural
        }
    }
}
