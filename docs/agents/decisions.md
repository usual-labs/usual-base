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
  Its icons get a rounded highlight under the pointer: one `NSBox` behind the stack that moves to the hovered
  button, from the bar's own tracking area (maintainer's request, 2026-11-08); the pointer turns into a hand over
  each button and the toolbar's flat buttons.
- **Inline formats wrap each line separately.** Markers can't span list items or paragraphs, so wrapping the whole
  selection would break the Markdown. When some lines have the format and some don't, the command adds it to the
  rest, as word processors do.
- **The window is frosted glass all the time** (maintainer's request, 2026-11-08): an `NSVisualEffectView`
  (`WindowGlass`, sidebar material, behind-window blending, state `.active`) as the window's container background,
  and text views that draw no background. SwiftUI's `.containerBackground(.thinMaterial, for: .window)` was tried
  first, but it turns opaque grey when the window isn't active, and the point is to see other windows through it.
  Reduce Transparency still makes it opaque.
  The window toolbar's background is explicitly hidden so the header adds no separate material over the shared
  window background; native toolbar controls retain their own styling.
- **The panes sit on the window's glass; the document sits on a Liquid Glass card** (the maintainer's sketch and
  request, 2026-11-08). `BaseWindow` lays out the file tree, the card and the History pane in an `HStack`: no
  `NavigationSplitView`, which adds its own sidebar glass, and no `HSplitView`, which draws divider lines across the
  glass and the toolbar. The 8 pt gaps beside the card resize the panes by dragging (`PaneResizer`); the widths
  and the History pane's visibility are app settings, the sidebar's visibility is per scene. The card is SwiftUI's
  `.glassEffect(.regular.tint(...))` with 12 pt corners, a second glass layer tinted 50% white, or 35% black in
  Dark Mode (the maintainer wanted it darker there); an opaque white card, plain `.regular` and `.clear` came first, each tried at the maintainer's request
  (2026-11-08). A tint mixes into the glass rather than lying over it: in captures a white tint made the card
  grayer in light mode and a lighter gray in Dark Mode, more so at 80%, where Dark Mode's quote text almost
  vanished. A brighter card needs a translucent fill under the text, not a stronger tint. Text on it is a little lighter than on white. Every scroll area (document, file tree, History) uses the thin overlay
  scroll bar (`ThinScrollView`, and `.thinScrollers()` for SwiftUI `ScrollView`s), whatever the "Show scroll bars"
  setting: the maintainer found the solid bar too heavy on the glass. Toolbar buttons and ⌃⌘S / ⌃⌘H
  show and hide the panes.
- **The file's name is its menu:** flat text with a chevron (`FileTitleMenu`) offering Rename…, Duplicate,
  Show in Finder, Copy Path and Move to Trash. The system title is removed, so a flexible `ToolbarSpacer` pushes the
  rest to the trailing edge. Renaming keeps the extension and the folder (`FileNames`) and doesn't rewrite links to
  the old name; Move to Trash asks nothing, since the Trash can put it back.
- **Spell checking marks prose only.** The editor's delegate refuses spelling marks on code, links and Markdown
  syntax such as link destinations (`EditorTheme.isProse`, read from the styled attributes), because notes full of
  file names and paths were covered in red underlines. Grammar and Writing Tools are unaffected.
- **Markdown colours are set per appearance** (`MarkdownColors` in BaseKit, shared by the editor and the viewer):
  code backgrounds, syntax characters and quiet text (quotes, list markers, done tasks). The system colours they
  replaced (`quaternarySystemFill`, tertiary and secondary label colours) drew code as near-black boxes and syntax
  too faint on the glass card in Dark Mode (maintainer's screenshot, 2026-11-08).
- **Icons are Lucide, as custom SF Symbols** (maintainer's choice, 2026-11-08): thin, plain line icons that suit
  the flat gray toolbar. Each is a symbol template in the asset catalog, not a plain SVG image or a Swift package, so
  it scales with the font, takes weights and tints, and works in AppKit (`NSImage(named:)`) and SwiftUI alike; a
  package would add a dependency for 29 files. SwiftDraw converts the SVGs with one fixed inset so every icon keeps
  Lucide's relative size (README). Lucide has no filled variants, so the properties card's "Yes" is an outlined
  check. The file tree's icons take the text's color, not the source list's accent tint (`FileCell`).
- **The sidebar lists every file and draws its own rows** (maintainer's reference screenshot, 2026-11-08). Markdown
  opens in the app; other files open in their own app, since the editor holds Markdown only. Rows are 28 pt with
  16 pt indents. Favorites (star) and the Base's name (library) are dividers with a small icon, a title and a hairline, not tree items: their rows
  sit at the top level, unindented, and they can't collapse; the dividers start at the margin, left of the
  chevrons (maintainer's request). A plain `NSOutlineView`
  (`SidebarOutlineView`, with a 10 pt leading margin) rather than a source list: a source list lays its own
  selection view over the row, solid accent with white text, and the design wants a soft accent tint with
  accent-coloured text (`SidebarRowView`, `SidebarColors`). Rows highlight under the pointer, a click on a folder
  opens or closes it, and only Markdown files can be selected, since the selection is the open document. Closing a
  folder that holds it deselects instead of letting the outline select the next file. A right-click rings its row
  with a rounded accent outline; the table's own square ring is turned off (`drawContextMenuHighlightForRow:`).
  The Icon submenu is one item holding a grid of every folder icon, icons only with names as tooltips
  (`IconGridView`): a list of 48 ran off the screen.
- **Favorites and folder icons are kept on this Mac**, per Base, in user defaults (`SidebarSettings`), so the app
  writes nothing into the Base's files; a rename or trash in the app carries a favorite along. They don't sync to
  other Macs yet; a file in the Base would, at the cost of a file every agent and git sees. A Favorites row can't
  expand: the outline needs every row's item to be unique, so a favorite folder reveals itself in the tree
  instead. A folder icon no longer offered falls back to the plain folder.
- **The toolbar is: sidebar button and the file's name on the left (no subtitle); the mode button above the card's
  trailing edge; then History, sync and Quick Open.** The mode button is one icon that shows what a click switches
  to, like the View menu's ⌘E command: a pencil in View, an eye in Edit. Every toolbar button and the name are flat,
  not glass (maintainer's request, 2026-11-08): gray (secondary) icons with a rounded highlight under the pointer
  (`FlatIconButtonStyle`, `hoverHighlight`). The title starts at the card's leading edge and the mode icon ends at its trailing
  edge (the maintainer's marked screenshot, 2026-11-08, after trying the text column and a 33 pt inset, both too far
  in). With History closed the mode icon stays just left of History, sync and Quick Open, which sit at the window's
  trailing edge. The window uses the compact toolbar (`.unifiedCompact`) for a shorter header, so the controls are
  28 pt tall. The toolbar doesn't know the layout, so a gap
  (`ToolbarGap`) inside the sidebar button's item and inside the mode button's item takes up the difference,
  computed from the pane widths and two offsets measured in a window capture (`titleStart`,
  `buttonsWidth`; remeasure when a toolbar button is added or moved, and note a larger `buttonsWidth` moves the mode
  icon right). The gaps live inside those items because the
  toolbar gives even an empty item 44 pt; every item hides the toolbar's shared glass. Highlights overhang without
  moving anything: the name's reaches 8 pt past the text, so the text and the pencil glyph line up with the card.
- **The panes slide and blur in and out** (0.3 s, `.smooth`): each pane keeps its width while the space for it
  opens or closes, clipped, going out of focus and fading as it closes. The title and the switch glide with them,
  because the gaps animate frame by frame. Hidden panes stay alive, so the file tree keeps its open folders; the
  History pane reads git only while shown.
- **History is the file's git log, read-only.** `BaseRepository.history(of:)` follows first parents (sync keeps
  history straight) and looks at no more than 2,000 commits. It runs on the `SyncEngine` actor, so it never
  overlaps a sync, and refreshes when the file, the sync status or the file on disk changes. Each row is an author,
  a relative date and the commit's first line; agents that commit under their own names show up by name.
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

- **Browser UI review is a passive Debug tool.** A separate local review build emits paired window captures and
  native frames; a token-protected loopback server serves plain HTML targets for Codex Browser annotations.
  AppKit owns the real interface and editing; the browser owns selection and presentation. It does not rebuild
  the app as HTML or accept input commands. Sample notes and a separate bundle identity isolate review from the
  user's Base. This keeps the first version small, adds no third-party dependency, and leaves Release untouched.
- **Agents learn Usual Base from one skill, `skills/usual-base/`,** in the Agent Skills format (`SKILL.md` plus
  `references/`), which Claude Code, Codex, Cursor and Hermes load. Agents without skills read it as
  instructions. Each feature has a row in the skill's feature table and, when it needs more than a paragraph, its
  own reference file. A feature that doesn't exist yet isn't mentioned.
- **The README's setup prompt only points at the skill.** The steps live in the skill's `references/setup.md`
  (`SKILL.md` keeps a short "Set up" section pointing there, so it loads only when needed), so there is one copy to
  keep current. The prompt has one blank, where the Base is; the skill comes from the public
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

## Hosted service

- **One Hono app, two platforms** (maintainer's request, 2026-11-09): Cloudflare for base.usual.dev, and Node for
  anyone to run in Docker. The app asks its platform for six things through `Env` (`src/env.ts`): the database,
  the repositories (`Repos`), publishing and watching push events, the sign-in limit, and background work. Each
  entry point builds it per request. The push check, the push log and the routes stay shared, so both behave the
  same; the end-to-end script is the proof for each.
  - **Node uses libSQL for the SQLite file**, because its Drizzle driver has `batch` like D1's, so the shared
    queries don't change. Migrations run at startup with Drizzle's migrator.
  - **Repositories on Node are bare repositories behind `git http-backend`**, git's own CGI server, created with
    `receive.denyNonFastForwards` and `receive.denyDeletes` as a second line behind the shared push check.
  - **WebSockets on Node use `ws` directly.** `@hono/node-ws` routes an upgrade through the app with an `env` of
    its own, which would replace the `Env`; instead the upgrade goes through `app.fetch` with an `Env` whose
    `watch` marks the request, so the token and Base checks are the same as everywhere.
  - **The Node server treats every request as addressed to `BASE_URL`**, as `wrangler dev` does with the route's
    host, so the dashboard's origin check works behind a proxy that terminates TLS.
- **One Worker serves everything at base.usual.dev:** dashboard, API and git, so agents allowlist one domain
  (maintainer's choice of domain and of keeping all of it public, 2026-11-08).
- **Accounts are Better Auth's email and password** (maintainer's choice over WorkOS and Clerk). Forms post to the
  app's own routes, which call `auth.api` directly; Better Auth's HTTP handler isn't mounted. Those calls skip its
  rate limit and origin checks, so the routes ask the platform's per-client sign-in limit (`allowAttempt`) and use
  Hono's `csrf()`.
- **The database goes through Drizzle** (maintainer's choice, 2026-11-09), Better Auth included, through its
  Drizzle adapter, so one schema file (`cloud/src/db/schema.ts`) describes every table and drizzle-kit writes the
  migrations, which Wrangler applies. Drizzle's stable line (0.45 ORM, 0.31 kit), not the 1.0 release candidate,
  whose migration folders Wrangler doesn't read. Times are Unix milliseconds throughout: Better Auth's as Dates
  (`timestamp_ms`), Usual Base's own as plain numbers.
- **Sign-ups are closed unless `SIGNUPS` allows them** ("open" or a list of emails, a Worker secret so no address is
  in the repository), because every Base is billed to the operator's Cloudflare account. Accounts are capped at
  50 Bases.
- **One Artifacts namespace, one repository per Base, named after the Base's id.** A binding is tied to one
  namespace; per-account namespaces would need the REST API.
- **Clients never see Artifacts tokens.** They use Usual Base tokens; the git proxy mints short-lived Artifacts
  tokens per request (cached per isolate). The proxy is needed anyway: Artifacts accepts force pushes and branch
  deletions (spike, 2026-11-08), and the proxy refuses them by walking the pushed commits back to the old head.
- **One device flow for the CLI and the apps.** The client shows a code, the person approves it in the dashboard
  and chooses Bases and access, and the client's poll mints the token then, so no token is stored in plain text.
- **Live updates come from the proxy, not Queue events:** every push passes through it, it tells the Base's
  Durable Object directly, and that answers keep-alive pings without waking. Queue events took up to 5 s.
- **The CLI is one Node file served by the server**, embedded at build time with the skill, so there's nothing to
  publish to npm and the CLI matches the server it came from. Its source is split by responsibility
  (`cli/usual-base.mjs` and `cli/lib/`), and `cloud/scripts/embed.mjs` bundles it with esbuild, already a build
  dependency. Run from a checkout, it uses the checkout's own skill and is updated with git.
- **The command is `usual-base`, also installed as `ubase`** (maintainer's choices, 2026-11-10). Usual is the whole
  lab, and its other CLI is `usual-ui`, so the full name matches the repository, the skill, `~/.config/usual-base/`
  and the `USUAL_BASE_*` settings; `ubase` is the short name people type. It's a link the installer and `update` add
  beside the CLI, never over another program's file. Messages and docs name `usual-base`. If the lab ever wants one
  `usual` command, `usual base …` can hand off to `usual-base` the way `git foo` runs `git-foo`.
- **Out of date means different from what the server serves** (2026-11-10): `update`, `doctor` and the daily check
  compare the CLI file and each skill file with the server's copies, not version numbers, so a deploy is enough. The
  daily check runs after commands that work with Bases, never after `credential` (git reads its output); it asks in
  a terminal and otherwise says so once on stderr, and an unreachable server is tried again next time. No command
  writes through a linked skill folder: on a maintainer's machine it leads into a checkout.
- **`usual-base init` makes the folder itself the Base** (maintainer's choice, 2026-11-10), where `import` uploads a
  copy. It refuses when both the folder and the Base have files rather than combining them, so it never mixes or
  overwrites files; a failed init removes the `.git` it made (or the folder, if it made that). It adds `.DS_Store`
  to `.git/info/exclude`, since the app's sync skips it too, sets `main` to follow `origin/main` from the start, and
  keeps the folder in the CLI's config, so `clone --all` and `path` use it (one folder per Base: the latest).
- **A Base can live inside a project** (maintainer, 2026-11-11: "the base folder path might be somewhere nested in
  the full claude code project folder"). It's a repository of its own, and the project's `.git/info/exclude`
  ignores it: local, so the project's tracked files don't change, and teammates set up their own. Not a submodule:
  the Base syncs by itself, never with the project's commits. A folder holding files the project tracks, a
  repository root, a folder inside another Base, and a folder holding git repositories are refused; the last
  would end up as broken links in the Base. Claude Code's plugin isn't installed inside a Base.
- **The Mac app creates and connects Bases with a wizard in the card** (maintainer, 2026-11-11: "a nice wizard … when
  nothing is connected, a cta should be to create a base or connect an existing to folder"). In the card rather
  than a sheet: it replaces the empty state in place, steps move with transitions, the sign-in sheet stays out of
  its way (the wizard shows the code itself), and the window capture can see it. Like the CLI it asks everything
  first and acts only on "Create Base" or "Connect Base"; a created Base is remembered, so trying again after a
  problem never creates a second. The sandbox only opens folders the person chooses, so "Inside a project" asks
  for the project folder itself, which lets the app write the project's `info/exclude`; the Base's folder there must
  be new or empty. Unlike the CLI, connecting into a folder with files is allowed: the app's sync already joins a
  folder with a Base that has notes, keeping the Base's version and a conflict copy of the folder's.
- **`usual-base init` without a folder, in a terminal, sets up the project there** (maintainer, 2026-11-11: "an
  interactive cli for initiating the base for a new project, or connecting it to it"). It asks everything first
  (connect if needed, which Base or a new one, where its folder goes, Claude Code's name and waking), shows what
  it will do and asks "Go ahead?"; only connecting happens before that. Offered folders: where the Base already
  is (inside the project first), `<project>/base`, the project itself, `~/Usual Base/<name>`; any typed folder is
  checked the same way. One command rather than a new one, since `init` already meant "make this a Base"; with a
  folder or a flag, or without a terminal, it works as before, for agents.
- **The server wakes agents on hosted platforms** (maintainer, 2026-11-11: "base.usual.dev making the call"). A
  Grok Bot runs only on a Cursor-hosted computer where a long-running relay isn't documented, while a routine's
  webhook is. The CLI announces each post rather than the server diffing every push, which would walk trees in
  Artifacts; the server reads the announced file itself, so a token can't wake anyone for a message that isn't in
  the Base. Each platform is a module behind `WakePlatform` (maintainer: "so the architecture would remain clean"),
  so Claude routines or OpenClaw go beside `grok-bot.ts`. Keys are sealed under a key derived from
  `BETTER_AUTH_SECRET`, so there's no new secret to deploy. Grok Bot setup is a prompt on the dashboard, not a CLI
  command: `connect --dir /workspace/...`, `room join --as`, and a routine the Bot creates in chat cover it.
- **A wake target belongs to an agent's name in rooms, not to its token** (2026-11-11). A user's Grok Bots share
  one computer and so one token, and a Bot whose computer is reset connects again with a new one; keyed by token,
  only one Bot could be woken and a reconnect left waking on the old token. Membership in a room, by name, is
  already the opt-in. The cost: revoking a token no longer stops waking; "Stop waking it" does, and the Agents page
  lists woken agents apart from connections.
- **Agents on one machine share one connection** (2026-11-11). Every agent there can read the CLI's config, so a
  token per agent would separate nothing, and a second `connect` used to replace the first agent's token and name
  silently. Now `connect` keeps a working connection and records the agent's name; `--again` replaces it and
  revokes the old token, since it was this machine's alone. Names stay per agent, and once two agents share a
  connection the CLI refuses to guess one: reading as another agent would mark its messages read.
- **The dashboard looks like the Usual family** (maintainer: "modern, minimal and nice … with a nice font, and smooth
  transitions", 2026-11-11). Figtree text and the Prociono `Usualbase` wordmark as on usual.dev, the app icon as
  logo and favicon, and the icon's monochrome palette: ink buttons, grays, one red for destructive actions. No CSS
  or JS framework: one stylesheet and a script that only adds conveniences, both embedded with hashed URLs, so
  the Node build needs nothing extra. Motion is cross-document view transitions plus short hover and focus
  transitions, all off under reduced motion; pages work without the script.
- **Claude Code gets a plugin, not hooks in project settings** (maintainer, 2026-11-11). Its monitor shows each room
  message as it arrives, even mid-task, so the before-prompt news is gone; its SessionStart hook still says who the
  agent is. Installed per repository with `--scope local`, so it stays project-specific. Plugins don't reach cloud
  sessions and monitors don't run under `-p`; cloud setup would need committed hooks instead.
- **Replies continue the session that asked** (maintainer, 2026-11-11): a room posted in from a person's Claude Code
  session is answered in that session, resumed by the relay once it's closed, never in a separate one while it's
  open, where resuming would mix two conversations.
- **Agents are set up per project, nothing global** (maintainer, 2026-11-10). Claude Code reads
  `.claude/settings.local.json` only at the repository root (and nested ones' are ignored), so one hook goes there and
  picks the deepest set-up project above the session's folder; nested repositories get their own. A woken agent may
  read and edit the Base and run `usual-base` (maintainer: "can also edit notes, along with the rooms"). Every message
  wakes every member at once (no burst delay), except for its own, under the loop brake and 20 wakes an hour; members
  are one file each, not a list in `ROOM.md`, because two agents joining at once would conflict in a list.
- **Rooms are files: one per message** (maintainer's choices, 2026-11-10), so writers never touch the same file and
  git never conflicts, on any remote. Names carry the time to the millisecond plus a random suffix (two messages in
  one minute must not collide), in a folder per UTC day so no commit rewrites a tree of every message and no folder
  nears Artifacts' 100,000-entry limit. `seen` (the maintainer's idea) records the newest message the writer had
  read; the CLI refuses to post while the writer has unread messages, the way git refuses a push until you pull.
  Unread messages are found through git (files added since the reader's commit), not by name, because names follow
  the writer's clock. Agents first: no fast lane through the Durable Object and no per-second pushes; push events
  plus `room wait` reach a waiting agent in about a second.
- **Open source doesn't need Cloudflare** (maintainer's choice, 2026-11-09). The app, the skill and the CLI's
  `sync`, `import --to` and `skill` work with any git repository; the app and CLI depend on the documented
  [server protocol](../protocol.md), not on base.usual.dev. `cloud/` is public too: the code behind base.usual.dev,
  which also runs on anyone's own server in Docker. Forgejo or Gitea work as well, with accounts, tokens and
  protected branches.
- **The Mac app keeps hosted clones in a folder chosen once**, not its container, so agents on the same Mac share
  them; the app is sandboxed, so it keeps a security-scoped bookmark to that folder.
