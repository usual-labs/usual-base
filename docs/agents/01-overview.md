# Usual Base: overview

## Built

**Local Markdown editor (2026-11-06).** It opens a folder (a Base) and shows its Markdown files in a sidebar and in
a styled TextKit 2 editor, with front matter as a properties card. Files save automatically. The app watches the
folder and reloads when files change outside it.

**View and Edit modes (2026-11-07).** A toolbar switch (⌘E). View renders the file natively, without its syntax:
real tables, task boxes, code and quote blocks, rules and pictures from the Base. It's read-only, and its links open
with a plain click. Edit is the styled source editor. The mode is remembered, and the app starts in View.

**Hosted Usual Base (2026-11-09).** `cloud/` is one Hono app (`src/app.ts`) with two entry points: a Cloudflare
Worker at base.usual.dev (D1, Artifacts, a Durable Object per Base, Workers rate limiting) and a Node server for
Docker (`cloud/Dockerfile`: a libSQL/SQLite file, bare repositories behind `git http-backend`, WebSockets held in
the process, an in-memory sign-in limit). Each builds the `Env` in `src/env.ts` per request. It has email-and-password
accounts (Better Auth, sign-ups limited by the `SIGNUPS` setting; every table through Drizzle), a server-rendered dashboard (Bases, agents
and devices, Connect an agent, approving a connection), a JSON API, and git at `/git/<base>.git` in front of one
repository per Base. Tokens (`ubt_…`, hashed) belong to an agent or a device, cover some Bases or all,
read or read-write. The git proxy refuses force pushes and branch deletions, records each push, and tells the
apps watching that Base over a WebSocket. The CLI (`cli/`, served bundled into one file; installed as `usual-base`
and `ubase`)
connects with the device flow, clones, syncs, makes a folder a Base where it is (`init`), imports a folder (snapshot, or `--history`, also of a subfolder) in
batches under Artifacts' limits, installs the skill, updates itself and the installed skills (`update`, and a daily
check that asks first), checks the setup (`doctor`), and is git's credential helper for the server. Without any
server it still syncs a clone, imports into an empty git repository (`--to <git url>`), and installs the skill
from the checkout it sits in. [docs/protocol.md](../protocol.md) is what the app and CLI expect from a server. Details: [cloud/README.md](../../cloud/README.md).

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

- **Hosted service (2026-11-09):** `npm run check` in `cloud/` (typecheck, 7 unit tests: pack parsing against real
  git packs, the fast-forward check, report-status, the sign-up rule). An end-to-end script against `wrangler dev`
  (local D1, real Artifacts namespace `usual-base-dev`) with the CLI in a throwaway HOME passed 31 checks: sign-up,
  cross-site form post refused, create a Base, `usual-base connect` approved in the dashboard, clone, private config
  file, sync, the push shown with the agent's name, force push and branch deletion refused, read-only token clones
  but gets 403 on push, 401 without a token, a WebSocket event on push, snapshot import with `.gitignore`,
  `--history` import of a subfolder, skill install, a denied connection, a revoked token refused, deleting a Base.
  Production smoke test after deploying: pages, `/install.sh`, `/cli/usual.mjs`, `/skill.json`, 401 for the API
  and git without a token, the sign-up gate (403) and a cross-site post (403).
- **Node and Docker (2026-11-09):** after the split into `src/app.ts` plus `src/cloudflare/` and `src/node/`,
  the same 41-check end-to-end script passed against `wrangler dev`, against the Node server (`npm start`, SQLite
  file in a scratch folder), and against the Docker image (built from the repository root, run as `node` with a
  named volume). In the container, the account survived a restart, migrations ran once, every Base's repository
  was gone after the script deleted them, and `docker stop` took under a second. Both type checks pass. Deployed
  to base.usual.dev the same day (no migration): the production smoke test passed, and the served CLI and skill
  files match the checkout byte for byte.
- **The CLI renamed `usual-base` (2026-11-10):** the end-to-end script, now installing the CLI through the
  server's `install.sh`, passed 47 checks against `wrangler dev` and against the Node server, including that
  nothing named `usual` is installed and `/cli/usual.mjs` answers 404. The 12 checks without a server passed too.
  Deployed the same day (no migration). On production, `/cli/usual.mjs` answers 404, the served CLI, installer
  and skill match the checkout byte for byte, and the installer puts `usual-base` in a scratch folder.
- **`usual-base init` (2026-11-10):** a 33-check script against `wrangler dev` and against the Node server passed: a
  folder with files becomes a new Base (committed without `.DS_Store` or ignored files, under the person's git name,
  tracking `origin/main`) and syncs; an empty folder gets an existing Base's notes; refusals (a Base with notes for
  a folder with files, a folder in a repository, an existing repository, no terminal and no flag, both flags, an
  unknown Base, a file over 32 MiB, a read-only token) leave the folder without `.git` and create no Base; in a
  terminal (driven by `expect`) a folder with files is offered only empty Bases, a wrong answer asks again, Enter
  takes the folder's name, and Ctrl-C changes nothing; `clone --all` and `path` use the init folder. The earlier 47
  and 12 checks still pass. Deployed with the next entry.
- **`ubase`, `update`, `doctor` and the daily check (2026-11-10):** with the CLI installed from the local server's
  `install.sh`, a 37-check script passed against `wrangler dev` and the Node server: `ubase` is a link that runs the
  CLI, survives a reinstall and leaves another program called `ubase` alone; git's token helper names the real file;
  `doctor` reports a healthy setup with exit 0, and finds an out-of-date CLI, a missing `ubase`, a missing token
  helper and an out-of-date skill (exit 1); `update` fixes all four; a skill folder linked elsewhere is never
  written by `skill` or `update`, and `doctor` only notes it; the daily check says so on stderr without a terminal
  and not again that day, asks in a terminal (Enter updates, n leaves it), and never runs for `credential`. The
  `init` (33), end-to-end (47) and no-server (12) scripts pass on the bundled CLI. Deployed the same day, with
  `init` (no migration; the first try hit D1's 7403 and the retry worked). On production the served CLI matches the
  bundle built from the checkout, the installer and skill match the checkout, `/cli/usual.mjs` is 404, and a fresh
  install in a scratch home gets `ubase`, a clean `doctor` (exit 0) and an `update` with nothing to do.
- **CLI without a server (2026-11-09):** a script with the server address on a closed port passed 12 checks:
  grouped help, the skill installed from the checkout byte for byte, `import --to` a bare repository (snapshot
  with `.gitignore`, and `--history` of a subfolder), a second import into a repository with history refused
  with nothing changed, `sync` pushing, rebasing onto another clone's push and pulling with no merge commits, a
  password in the address not echoed, and server commands asking to connect. The hosted end-to-end script then
  passed 41 checks, including a CLI downloaded from the server installing the server's skill. Deployed with the
  platform split (above).
- **Drizzle (2026-11-09):** after the move to Drizzle, the end-to-end script passed 40 checks twice on a fresh
  local database: the 31 above plus a token limited to one Base (reads it, 404 on another, named on the agents
  page), a connection approved for one Base and read only, and deleting every Base it made. drizzle-kit reports no
  schema changes against the generated migration. Deployed the same day; the production smoke test passed again,
  plus paths that read the database without writing: an unknown token (401 for the API and git), an unknown
  device code ("expired"), and signing in to an unknown account (Better Auth's error, not a crash).
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

- **The hosted service in use:** nobody has signed up or connected an agent on production yet.
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
