import AppKit

/// Colours the editor and the viewer share. The system fills turned code backgrounds near black on the document's
/// glass card in Dark Mode, and the label colours for syntax and quotes were hard to read there, so these are set
/// per appearance.
public enum MarkdownColors {
    /// Behind code blocks, inline code and table headers.
    public static let codeBackground = dynamic(
        light: NSColor(white: 0, alpha: 0.05), dark: NSColor(white: 1, alpha: 0.09))
    /// Quotes, list markers, done tasks and captions: quieter than body text but still easy to read.
    public static let secondary = dynamic(light: NSColor(white: 0, alpha: 0.6), dark: NSColor(white: 1, alpha: 0.7))
    /// Markdown's own characters in the editor: `#`, `**`, backticks, link destinations.
    public static let syntax = dynamic(light: NSColor(white: 0, alpha: 0.35), dark: NSColor(white: 1, alpha: 0.5))

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}
