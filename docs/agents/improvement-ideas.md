# Usual Base: improvement ideas

Deferred work, roughly in the order the product plan needs it. Status is open unless noted.

- **Live native UI review inside Codex Browser.** Research on 2026-11-08 found
  [AppKit Inspector](https://github.com/JaminZhou/AppKitInspector), a public-preview Codex plugin with a
  Debug-only in-process probe. Its README documents native view hierarchy, refreshable captures and semantic
  targets for Codex Browser comments. Browser clicks select views; browser-to-app input forwarding is not
  documented. Usual Base's SwiftUI-hosted controls need a compatibility check. Nothing installed or verified
  locally. [Build macOS Apps + Browser Mirror](https://github.com/MarcoRossini96/build-macos-apps-browser-mirror)
  provides a live selected-window feed, but explicitly has a read-only viewer, without native element annotations.
  Neither is yet verified to satisfy the full request: operating the app, inspecting elements and commenting
  from the same live browser panel.
- **A "Set Up an Agent…" sheet in the app** that fills in the open Base's path and remote and copies the setup
  prompt. Ship the skill inside the app bundle, so local agents can copy it from there and the prompt has no
  blanks.
- **Keep the reading position when switching between View and Edit**, by mapping the top visible block to its
  source line. Today the other mode opens at the top.
- **Tick tasks in View mode**, writing `[x]` into the source at the box's position.
- **Formatting bar:** a code block for code over several lines (it wraps each line in backticks today), shortcuts
  for lists, and the bar in View mode once rendered text maps back to its source.
- **Load web pictures in View mode**, asynchronously, and render on a background thread for very large files.
- **History view:** for the open file, who changed it and when, with diffs, from git history. Replayed commits keep
  their authors, so this works for agents that commit under their own names.
- **Merge the open file's unsaved edits** with a change that arrives from outside, using `git_merge_file`, instead
  of saving them as a conflict copy when the edits don't overlap.
- **Hosted Usual Base:** live updates over a WebSocket from Cloudflare (Artifacts push events) instead of polling
  every minute. The plan is in the parent workspace.
- **SSH remotes**, with a key the app creates and keeps in the keychain (the sandbox can't read `~/.ssh`).
- **A URLSession HTTPS transport for libgit2**, if SecureTransport's TLS 1.2 limit or deprecation starts to bite.
- **Commit messages that say when a replay became a conflict copy.**
- **File actions:** new file, rename, delete and reveal in Finder from the sidebar.
- **Full-text search across the Base.**
- **Properties:** edit a single property inline, changing only its line.
- **Hide syntax away from the cursor**, Obsidian-style. Needs TextKit 2 layout-fragment work.
- **Syntax colours inside fenced code blocks.**
- **Restyle only the blocks that changed** and use rendering attributes for colours, if large files feel slow.
- **Pointer feedback** over task boxes and links (⌘-hover).
- **A margin showing which agent last changed each paragraph**, from git history.
- **Release signing and a Homebrew cask,** following Usual Bot's setup.
- **An Icon Composer `.icon`** for Liquid Glass, dark and tinted icon variants. Today `AppIcon` is a plain
  full-bleed image that macOS rounds itself, as in Usual Bot.
