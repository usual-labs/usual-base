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
  copy. It refuses when both the folder and the Base have files rather than combining them, and refuses a folder in
  a git repository (`import --history` covers those), so it never mixes or overwrites files; a failed init removes
  the `.git` it made. It adds `.DS_Store` to `.git/info/exclude`, since the app's sync skips it too, and keeps the
  folder in the CLI's config, so `clone --all` and `path` use it (one folder per Base: the latest).
- **The server wakes agents on hosted platforms** (maintainer, 2026-11-11: "base.usual.dev making the call"). A
  Grok Bot runs only on a Cursor-hosted computer where a long-running relay isn't documented, while a routine's
  webhook is. The CLI announces each post rather than the server diffing every push, which would walk trees in
  Artifacts; the server reads the announced file itself, so a token can't wake anyone for a message that isn't in
  the Base. Each platform is a module behind `WakePlatform` (maintainer: "so the architecture would remain clean"),
  so Claude routines or OpenClaw go beside `grok-bot.ts`. Keys are sealed under a key derived from
  `BETTER_AUTH_SECRET`, so there's no new secret to deploy. Grok Bot setup is a prompt on the dashboard, not a CLI
  command: `connect --dir /workspace/...`, `room join --as`, and a routine the Bot creates in chat cover it.
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
