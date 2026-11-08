import AppKit
import BaseKit
import SwiftUI

@main
struct UsualBaseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Usual Base", id: "base") {
            BaseWindow()
                .environment(appDelegate.base)
                .task { appDelegate.base.restoreLastBase() }
                .containerBackground(for: .window) { WindowGlass() }
        }
        .defaultSize(width: 1180, height: 820)
        .commands { BaseCommands(base: appDelegate.base) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let base = BaseModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
            DebugSnapshot.scheduleIfRequested()
        #endif
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [base] _ in
            MainActor.assumeIsolated { base.document?.saveNow() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [base] _ in
            MainActor.assumeIsolated { base.sync.appBecameActive() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        base.document?.saveNow()
    }
}

struct BaseCommands: Commands {
    let base: BaseModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Base…") { base.chooseBase() }
                .keyboardShortcut("o")
            Button("Quick Open…") { base.isQuickOpenShown = true }
                .keyboardShortcut("p")
                .disabled(base.root == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { base.document?.saveNow() }
                .keyboardShortcut("s")
                .disabled(base.document == nil)
            Divider()
            Button("Sync Now") { base.sync.syncNow() }
                .disabled(base.sync.status == .off)
            Button("Sync Settings…") { base.sync.isSetupShown = true }
                .disabled(base.root == nil)
        }
        TextEditingCommands()
        CommandMenu("Format") {
            formatButton(.bold).keyboardShortcut("b")
            formatButton(.italic).keyboardShortcut("i")
            formatButton(.strikethrough).keyboardShortcut("x", modifiers: [.command, .shift])
            formatButton(.code)
            formatButton(.link).keyboardShortcut("k")
            Divider()
            formatButton(.heading(1)).keyboardShortcut("1", modifiers: [.command, .option])
            formatButton(.heading(2)).keyboardShortcut("2", modifiers: [.command, .option])
            formatButton(.heading(3)).keyboardShortcut("3", modifiers: [.command, .option])
            formatButton(.heading(0)).keyboardShortcut("0", modifiers: [.command, .option])
            Divider()
            formatButton(.bulletList)
            formatButton(.numberedList)
            formatButton(.taskList)
            formatButton(.quote)
        }
        CommandGroup(after: .toolbar) {
            Button(base.mode == .view ? "Edit Markdown" : "View Rendered") {
                base.mode = base.mode == .view ? .edit : .view
            }
            .keyboardShortcut("e")
            .disabled(base.document == nil)
        }
    }

    /// A Format command for the editor that has the keyboard focus.
    private func formatButton(_ format: MarkdownFormat) -> some View {
        Button(format.title) {
            (NSApp.keyWindow?.firstResponder as? MarkdownTextView)?.format(format)
        }
        .disabled(base.mode != .edit || base.document == nil)
    }
}
