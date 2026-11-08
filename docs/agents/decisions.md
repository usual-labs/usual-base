# Usual Base: decisions

## Editor

- **The editor is native, on TextKit 2: Apple's `NSTextView`, not CodeMirror in a web view.** This was the
  maintainer's choice on 2026-11-06. It brings the system's text features (spelling, input methods, lookup, Writing
  Tools) with no web process. The cost is that the Markdown editing layer is ours to write.
- **The editor shows styled source, not WYSIWYG.** The Markdown syntax stays visible but dimmed. A WYSIWYG editor
  re-serializes Markdown and would rewrite agents' formatting. Hiding syntax is deferred because TextKit 2 has no
  way to hide individual characters.
- **swift-markdown is the parser, not tree-sitter-markdown.** swift-markdown is built on cmark-gfm and is correct;
  tree-sitter-markdown's own README advises against using it where correctness matters. swift-markdown re-parses
  the whole document after each edit, off the main thread. A 490 KB file takes 18 ms in a release build.
- **The editor holds only the body.** Front matter lives in `MarkdownFile.frontMatter` and the card. Its YAML is
  edited as raw text and written back between the original fence lines, so keys, comments and formatting survive.
- **Saves check the disk first.** A save happens only if the file still holds the bytes last read or written.
  Otherwise the app's version becomes `Name (conflict yyyy-MM-dd HH.mm).md` and the editor loads the version on
  disk. The check and the write aren't atomic; git history is the backstop.
- **Every FSEvents batch re-reads the open file.** Comparing bytes is cheaper and more reliable than matching event
  paths, which FSEvents reports with symbolic links resolved and which atomic saves rename.
- **The sidebar uses `NSOutlineView`.** It builds only the rows on screen. The tree comes from the file index, so
  only folders that contain Markdown appear.
- **The app is sandboxed** and keeps an app-scoped security bookmark to reopen the last Base. It has the
  outgoing-network entitlement for sync.
- **Formatting works in Edit mode only, by writing Markdown markers.** View is read-only, and editing there would
  need a map from rendered text back to the source. Every command is a toggle, so the bar needs no separate
  "remove" buttons, and it lights up what the selection already has.
- **The formatting bar lives inside the text view**, as a subview on `NSGlassEffectView`, not a popover or child
  window. It scrolls with the text, can't take the focus, and needs no window management. A selection that is
  still being dragged hides it, so it doesn't jump while the mouse moves.
- **Inline formats wrap each line separately.** Markers can't span list items or paragraphs, so wrapping the whole
  selection would break the Markdown. When some lines have the format and some don't, the command adds it to the
  rest, as word processors do.
- **The window is frosted glass all the time** (maintainer's request, 2026-11-08): an `NSVisualEffectView`
  (`WindowGlass`, sidebar material, behind-window blending, state `.active`) as the window's container background,
  and text views that draw no background. SwiftUI's `.containerBackground(.thinMaterial, for: .window)` was tried
  first, but it turns opaque grey when the window isn't active, and the point is to see other windows through it.
  Reduce Transparency still makes it opaque.
- **The internal extension seam is a table, not a plugin API yet.** A new style is a `StyleSpan.Kind` plus a case
  in `EditorTheme`. A new editing helper is a `MarkdownEditing` function plus a command in the coordinator.

## View mode

- **View renders natively with TextKit 1, not a web view or SwiftUI views.** The renderer builds an attributed string
  with `NSTextTable` for tables and `NSTextBlock` for quotes and code, so the page is one text view: selection runs
  across blocks, and copy and ⌘F work as in any document. Only TextKit 1 lays out text tables, so the
  viewer is TextKit 1 from the start; the editor stays on TextKit 2. A SwiftUI view per block (MarkdownUI, Textual)
  can't select across blocks.
- **Edit is the styled source editor; there is no live preview.** Agents' formatting stays untouched because only
  Edit writes, and it writes the source.
- **View is read-only.** Ticking tasks there is deferred.
- **The renderer uses swift-markdown, the editor's parser,** so both modes read a file the same way.
- **The app starts in View and remembers the last mode** (UserDefaults `documentMode`). Most of a Base is written
  by agents and read by people.
- **Raw HTML shows as dimmed source,** since nothing can draw it without a web view; comments are hidden, as on
  GitHub, and `<br>` breaks the line. Pictures load only from files inside the Base; web pictures show as a linked
  description.

## Agents

- **Agents learn Usual Base from one skill, `skills/usual-base/`,** in the Agent Skills format (`SKILL.md` plus
  `references/`), which Claude Code, Codex, Cursor and Hermes load. Agents without skills read it as
  instructions. Each feature has a row in the skill's feature table and, when it needs more than a paragraph, its
  own reference file. A feature that doesn't exist yet isn't mentioned.
- **The README's setup prompt only points at the skill.** The steps live in the skill's "Set up" section, so there
  is one copy to keep current. The prompt has one blank, where the Base is; the skill comes from the public
  repository.
- **A Base's own `AGENTS.md`, at its root, overrides the skill's defaults** for how that Base is organized. People
  can read and edit it in the app like any note.
- **Agents on the Mac commit under their own name but don't push;** the app pushes. Agents in clones elsewhere
  pull with rebase, commit and push, and never force-push. Both keep history straight and credited, which the
  planned history view and per-paragraph attribution need.

## Sync

- **Git is the sync protocol, through libgit2.** Any git host works, agents in the cloud can clone the same
  repository, and history records who changed what. libgit2 runs in the sandbox, which `/usr/bin/git` (an Xcode
  shim that reads `~/.gitconfig` and credential helpers) doesn't.
- **libgit2 is compiled from vendored source**, not a prebuilt binary or Homebrew: no binary blobs, no CMake, and
  the build settings are ours. HTTPS uses the system's TLS (SecureTransport), SHA-1 uses collision detection like
  git, and SSH is left out. The sources are copied by `scripts/vendor-libgit2.sh`, not a submodule, so a plain
  clone builds in Xcode.
- **The Base folder is an ordinary clone, with `.git` inside.** This replaced the product plan's proposal to keep
  git metadata outside the folder: an existing clone can be opened as is, agents on this Mac can read the history
  with plain git, and standard tools keep working. Hidden folders never show in the sidebar.
- **Sync is opt-in per repository** (`usualbase.sync = true` in its `.git/config`). A code repository opened as a
  Base never starts committing and pushing on its own.
- **Local commits are replayed onto the remote's, not merged.** History stays a straight line and each commit
  keeps its author, which a per-file history view will need. Local history that contains merge commits gets one
  merge commit instead, since replaying would flatten it.
- **A clash keeps the remote's version at the path and this Mac's as a conflict copy**, committed and pushed so
  every clone sees both. A file one side deleted and the other changed is kept. Git's three-way merge resolves edits
  to different lines of the same file without a copy. There are no CRDTs.
- **The checkout is git's safe checkout against the last commit.** A file that changed since the sync committed is
  never overwritten; the sync stops with `folderChanged` and runs again once the folder is quiet.
- **When to sync:** 5 seconds after the folder goes quiet, without fetching unless the push is refused; every
  60 seconds and on activation, with a fetch. Hosted remotes such as Cloudflare Artifacts bill each git operation,
  so typing doesn’t push on every pause, and an app left open fetches about 1,400 times a day. The hosted version is
  meant to replace polling with push notifications.
- **HTTPS with a token, kept in the login keychain** (one item per remote address). The token is sent as the
  password of basic auth, which GitHub, GitLab and Cloudflare Artifacts all accept. A token pasted inside the
  address is split off so it never lands in `.git/config`. SSH is deferred: the sandbox can't read `~/.ssh`.
- **Commit author:** what the setup sheet saved, else the repository's `user.name` and `user.email`, else
  `user@host` as git itself would use. App commits are named after what changed ("Update notes.md", "Add 3 files").
