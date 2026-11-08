# Usual Base: overview

## Built

**Local Markdown editor (2026-11-06).** It opens a folder (a Base) and shows its Markdown files in a sidebar and in
a styled TextKit 2 editor, with front matter as a properties card. Files save automatically. The app watches the
folder and reloads when files change outside it.

**View and Edit modes (2026-11-07).** A toolbar switch (⌘E). View renders the file natively, without its syntax:
real tables, task boxes, code and quote blocks, rules and pictures from the Base. It's read-only, and its links open
with a plain click. Edit is the styled source editor. The mode is remembered, and the app starts in View.

**Formatting bar (2026-11-08).** In Edit mode, selecting text shows a bar of format buttons above it, on Liquid
Glass. The Format menu has the same commands. Each one toggles: it adds the Markdown markers, or takes them off when
the selection already has the format, and the bar lights up the formats the selection has.

**App icon (2026-11-08).** The Base concept from `../design/logo/2026-11-08-usual-base/`: three slabs centred on
a white 1024 tile, full-bleed, in `App/Assets.xcassets`. macOS 26 rounds it like any icon. The README shows it too.

**Glass window (2026-11-08).** The whole window is frosted glass: the desktop and other windows show through,
blurred, even when the app isn't active.

**Git sync (2026-11-06).** A Base can sync with any git repository over HTTPS with a token. The folder is an
ordinary clone (`.git` inside). Sync is opt-in per Base (`usualbase.sync` in the repository's config). There's no
hosted service, account or history view yet.

**Agent skill and setup prompt (2026-11-07).** `skills/usual-base/` teaches agents to find, read, search and
write a Base, how notes render, and how sync and conflict copies work. It also has a "Set up" section. The
README's "Set up your agents" prompt hands an agent to that section.

### How the pieces fit

- **`BaseKit`** (Swift package, tested):
  - `MarkdownFile` splits a file losslessly into front matter and body.
  - `FrontMatter` reads YAML for display.
  - `MarkdownHighlighter` turns swift-markdown's tree into `StyleSpan`s with UTF-16 ranges, using `SourceMap`.
  - `MarkdownRenderer` (with `+Inline` and `+Table`) turns the same tree into an `NSAttributedString` for View mode:
    markers and tab stops for lists, `NSTextBlock`s for quotes, code and rules, and `NSTextTable` for tables, with
    columns sized by their text. It needs TextKit 1. `BareURLs` finds plain `https://…` text for both.
  - `MarkdownEditing` holds the editing helpers as pure text transforms. `MarkdownFormat` (with `+Lines`) adds the
    Format commands: inline formats work on each selected line's text, past its list or heading marker, and peel
    nested markers (`~~**x**~~`) in any order; line formats replace each line's marker and keep the selection on
    the same text.
  - `BaseIndex` and `FileNode` provide the file list, quick-open ranking and tree.
  - `FolderWatcher` wraps FSEvents.
  - `DocumentStore` saves with conflict copies; `ConflictCopy` names them for saves and syncs alike.
  - `Git/`: `BaseRepository` is the sync engine on libgit2. One `sync` call commits the folder's changes, fetches
    `origin`, replays local commits onto the remote's (or merges when local history has merges), checks the result
    out safely and pushes, retrying up to three times when the push is refused. `RemoteAddress` checks an address
    and splits off pasted credentials. `Libgit2.swift` holds the small C-interop helpers.
  - `Vendor/libgit2` is libgit2's source, compiled as the `Clibgit2` target; `CGitShim` wraps the variadic
    `git_libgit2_opts`.
- **App:**
  - `BaseModel` owns the open folder, the security-scoped bookmark, rescans, link opening, loading pictures from
    the Base, the View/Edit mode (saved in UserDefaults) and the `SyncController`. Leaving Edit saves first.
  - `OpenDocument` owns one file's saving and reloading.
  - `WindowGlass` is the window's background, behind every column. `DocumentTextView` is the shared text view: a
    readable centred column and the properties card above it, with no background of its own.
  - `MarkdownEditor` hosts `MarkdownTextView` (TextKit 2) and an `EditorCoordinator`. The coordinator re-highlights
    shortly after each edit, in the background, and applies the result through `EditorTheme`.
  - `FormattingBar` is a subview of `MarkdownTextView`, so it scrolls with the text. The view places it above the
    visible part of the selection (below it when there's no room), from TextKit 2's selection segments, after a
    drag-selection ends and again after restyling. Its buttons refuse first responder, so the text view keeps the
    focus and the selection. The Format menu sends commands to the focused `MarkdownTextView`.
  - `MarkdownViewer` hosts a read-only `DocumentTextView` on TextKit 1. Its coordinator renders the body again when
    the file changes on disk, keeping the scroll position.
  - `BlockLayoutFragment` draws code backgrounds and quote bars.
  - `Sync/`: `SyncController` decides when to sync (5 s after the folder goes quiet, without fetching unless the
    push is refused; every 60 s and on activation, with a fetch) and holds the status. `SyncEngine` is an actor on
    its own dispatch queue that owns the `BaseRepository`. `CredentialStore` keeps tokens in the login keychain.
    `SyncStatusButton` and `SyncSetupView` are the UI.
- **Styling flow:** text, then spans in BaseKit, then attributes in `EditorTheme`. The editor holds only the body;
  the card shows the front matter.
- **Sync and the editor:** the open document is saved before each sync. A pulled change to the open file arrives as
  a file-system event and reloads it, or ends in a conflict copy if it has unsaved edits. A sync clash on the open
  file shows the same notice.

## Verified

- **Checks:** `scripts/check.sh` passes: swift-format lint, 65 BaseKit tests and an unsigned macOS build, with
  Xcode 27.1 and the macOS 27 SDK; the deployment target is macOS 26.
- **Sync tests** (two Bases and a bare repository on disk, git CLI as a second opinion): publish byte for byte (BOM
  and CRLF) without `.DS_Store`, pull, clean merge of different lines with straight history and kept authors, the
  remote's version plus a conflict copy for clashing lines, edit-versus-delete keeps the edit, a refused push
  fetches and retries, joining a remote that already has files, a file written mid-sync is never overwritten, and
  existing clones don't sync until connected.
- **HTTPS** (opt-in `GitNetworkTests`, 2026-11-06): fetching a public GitHub repository works through the system's
  TLS, and a refused token is reported as `authenticationFailed`.
- **Running app, without the sandbox, against a bare repository on disk (2026-11-06):**
  - opening a connected Base committed and pushed it
  - a file written into the folder was committed and pushed 5 s later; the push was refused because another
    clone had pushed, so the app fetched, replayed and pushed, keeping history straight
  - the other clone's edit reached the folder
  - clashing edits to the open file left the remote's version open, a conflict copy in the sidebar and the notice
- **Sandboxed app (2026-11-06):** a Base in the app's container connected to a public GitHub repository fetched
  over HTTPS, checked out its files and took the remote's default branch name (`master`).
- **View mode (2026-11-07):** 11 renderer tests (syntax removed, styles, links and bare URLs, nested and ordered
  lists, tasks, table cells with alignment and column widths, code, quotes, HTML, pictures, spacing). Debug
  snapshots of a sample note with every block kind, in light and dark mode, show the rendering as intended. A
  generated 218 KB note dense with tables and code renders in 0.24 s in a release build; a 9 KB note in 9 ms.
- **Formatting bar (2026-11-08):** 10 `MarkdownFormatTests` cover every command, adding and taking off, nested
  markers, several lines, CRLF and multi-byte text, and which formats a selection has. Debug snapshots with text
  selected (`USUALBASE_SELECT`) show the bar above the selection, with Bold lit on bold text and Bulleted List on a
  list line. The snapshot doesn't draw the glass behind it.
- **App icon (2026-11-08):** the Debug build carries `AppIcon.icns` and `Assets.car`, and `NSWorkspace` draws the
  built app's icon as a rounded white tile with the slabs centred. Not seen in the Dock or Finder by a person yet.
- **Glass window (2026-11-08):** lldb on the running Debug app shows `WindowGlass`'s `NSVisualEffectView` filling
  the window behind the content (sidebar material, behind-window, always active) with a window-server-aware
  backdrop blur, and the text views drawing no background. Not seen by eye: screen capture isn't permitted here, so
  readability over busy backgrounds, light and dark mode, and the sidebar's glass on top are unchecked.
- **Editor:** debug snapshots on a sample Base show every span kind, including the properties card, hanging
  indents, quote bars and code blocks, in light and dark mode. Outside edits reload the open file, and opening a
  file leaves its bytes unchanged.
- **Highlighter speed:** a 490 KB Markdown file takes 18 ms in a release build and 53 ms in a debug build.

## Not verified yet

- **Sync with credentials:** pushing to a private GitHub repository or Cloudflare Artifacts with a token, the
  keychain item (including prompts after rebuilds of an ad-hoc-signed app) and the setup sheet's flow.
- **Sync at scale:** thousands of files, large first commits, and how long a sync blocks on a slow network.
- **Interactive behaviour**, from keyboard and mouse:
  - typing and the editing helpers in the running app (they're unit-tested as text transforms)
  - the formatting bar by mouse: its glass look, clicks, the heading menu, Undo, and placement while scrolling or
    near the window's edges
  - task clicks, ⌘-click links and paste-to-link
  - the properties card's YAML editing
  - the sync popover, Sync Now and Stop Syncing
  - switching modes with unsaved edits, link clicks, selection, copy and ⌘F in View mode
  - Quick Open's keyboard navigation
- **The agent skill in use:** no agent has run the setup prompt or used the skill on a real Base yet.
- **Inline Writing Tools**, input methods and VoiceOver.
- **Restyling cost and scrolling** on very large files in the running app.
- **The sandboxed build with a real folder picked in the open panel**, and reopening it from the bookmark.
