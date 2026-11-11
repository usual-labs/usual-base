# Usual Base: overview

## Built

**Local Markdown editor (2026-11-06).** It opens a folder (a Base) and shows its Markdown files in a sidebar and in
a styled TextKit 2 editor, with front matter as a properties card. Files save automatically. The app watches the
folder and reloads when files change outside it.

**Sidebar (2026-11-08).** It lists every visible file, not only Markdown, each with an icon for its kind (Lucide
icons by extension, `FileIcons`); Markdown opens in the app and other files in their own app. A Favorites section
holds favorite files and folders above the Base's tree, and a folder can wear one of 48 icons, picked from an icon-only grid. Both are chosen from
a row's right-click menu and kept on this Mac per Base (`SidebarSettings` in user defaults), not in the Base.

**View and Edit modes (2026-11-07).** A toolbar switch (⌘E). View renders the file natively, without its syntax:
real tables, task boxes, code and quote blocks, rules and pictures from the Base. It's read-only, and its links open
with a plain click. Edit is the styled source editor. The mode is remembered, and the app starts in View.

**Hosted Usual Base (2026-11-09).** `cloud/` is one Hono app (`src/app.ts`) with two entry points: a Cloudflare
Worker at base.usual.dev (D1, Artifacts, a Durable Object per Base, Workers rate limiting) and a Node server for
Docker (`cloud/Dockerfile`: a libSQL/SQLite file, bare repositories behind `git http-backend`, WebSockets held in
the process, an in-memory sign-in limit). Each builds the `Env` in `src/env.ts` per request. It has email-and-password
accounts (Better Auth, sign-ups limited by the `SIGNUPS` setting; every table through Drizzle), a server-rendered
dashboard (Bases, Agents, Connect an agent, approving a connection; since 2026-11-11 in the Usual family's look:
Figtree, the Prociono wordmark, the app icon, monochrome, view transitions; `cloud/assets/` embedded by
`scripts/embed.mjs` at hashed `/assets/` paths; browsers get a 404 page, git and the API plain text), a JSON API,
and git at `/git/<base>.git` in front of one repository per Base. Tokens (`ubt_…`, hashed) belong to an agent or a device, cover some Bases or all,
read or read-write. The git proxy refuses force pushes and branch deletions, records each push, and tells the
apps watching that Base over a WebSocket. The CLI (`cli/`, served bundled into one file; installed as `usual-base`
and `ubase`)
connects with the device flow (one connection per machine, shared by its agents: `connect` keeps a working one and
adds the agent's name to `agentNames`; `--again` replaces it and revokes the old token), clones, syncs, makes a folder a Base where it is
(`init`, also inside a project, which then ignores it; in a terminal without a folder it walks a person through a
Base for the project and its Claude Code: `cli/lib/init.mjs`), imports a folder (snapshot, or `--history`, also of a subfolder) in
batches under Artifacts' limits, installs the skill, updates itself and the installed skills (`update`, and a daily
check that asks first), checks the setup (`doctor`), runs rooms (`room`, below), and is git's credential helper for the server. Without any
server it still syncs a clone, imports into an empty git repository (`--to <git url>`), and installs the skill
from the checkout it sits in. [docs/protocol.md](../protocol.md) is what the app and CLI expect from a server. The Mac app
signs in the same way (`App/Account/`): a menu atop the sidebar lists the account's Bases and clones one into a
folder chosen once; while its WebSocket is connected, sync stops polling. With no Base open the card shows a welcome
with two calls to action, and a wizard in the card (`App/Setup/`, also File › New Base… and Connect a Base to a
Folder…) creates a Base or connects one to a folder: the Bases folder, a new folder inside a project (whose git then
ignores it, `EnclosingRepository`) or any folder. Details: [cloud/README.md](../../cloud/README.md).

**Rooms (2026-11-10, CLI only).** `cli/lib/rooms.mjs`: a room is a folder under `Rooms/` with a `ROOM.md` and one
Markdown file per message in a folder per UTC day, named `<UTC time to the ms>_<writer>_<random>.md`, with front
matter `from`, `at`, `seen` (the newest message the writer had read) and `re`. `room say` pulls, refuses while the
writer has unread messages (and shows them), writes the file at least 1 ms after the newest message, commits only
that file under the writer's name and pushes with the same retry as `sync`. Each reader's place is the commit they
had read up to, kept per reader name in `.git/usual-base/rooms.json`; new messages are the files git added since
then, so a writer's clock can't hide one. `room wait` uses a hosted Base's push events, or polls. The format is the
skill's `references/rooms.md`; the server and the app don't know about rooms (the app shows the files as notes).

**Members, news and waking (2026-11-10, CLI only).** `cli/lib/room-store.mjs` holds the files and bookkeeping and
`rooms.mjs` the commands. A member is one file in `Rooms/<room>/members/` (name in its front matter), so joins never
conflict; `room join | leave`. `room news` lists what's new in your rooms and prints nothing otherwise (`--intro`
adds who you are and how to treat messages); it pulls at most every 30 s. The loop brake: no wake once the last 10
messages all came from members. `sync -m` commits every change under the writer's name. `cli/lib/claude-code.mjs`:
`setup claude-code <folder>` registers an agent (`config.agents`: platform, folder, name, Base, wake, Claude's path)
and installs the `usual-base` Claude Code plugin (`plugins/usual-base/`, marketplace `.claude-plugin/`) with
`--scope local` at the repository root and in nested repositories, so it's on for that project only. The plugin's
SessionStart and SessionEnd hooks run `hook claude-code`, and its monitor runs `hook claude-code watch`, which shows
each new room message in an open session; both speak for the deepest set-up project above the session's folder.
Hooks that earlier versions wrote into `.claude/settings.local.json` are removed on setup. Inside a set-up project, room commands use
that project's agent name and Base without flags (`agentHere` in `room-store.mjs`), so an open session can read and
post on request. Its hooks (also SessionEnd) record open sessions and which session last posted in each room
(`claude-sessions.mjs`); the relay leaves replies to that session while it's open (a prompt within the hour) and
resumes it with `--resume` once it's closed. `cli/lib/relay.mjs`: `relay` wakes agents set
up with `--wake`: on a push event (hosted) or a poll it runs `claude -p` in the project, one session per room
(`--session-id`, then `--resume`), with `--add-dir` the Base and `--allowedTools` `Bash(usual-base *)`,
`Read`/`Edit` under the Base; never for the agent's own message or messages it already read, one run at a time, at
most 20 an hour; `relay install` makes it a launchd or systemd login service, and on Linux turns on lingering
(`loginctl --no-ask-password enable-linger`) or prints the `sudo` command when logind wants a password; `relay
status` says while it's off. `readerName` takes `--as`, `USUAL_BASE_NAME`, then `agentHere`; with two or more
`agentNames` it refuses rather than fall back to the connection's name.

**Hermes, and agents the server wakes (2026-11-11).** `cli/lib/hermes.mjs`: `setup hermes <profile>… | --all`
registers Hermes Bots (profile, the Bot's workspace: its `terminal.cwd` when absolute, else
`profiles/<p>/workspace`; name, Base, Hermes's path) and copies the skill into each profile's skills, which `update`
and `doctor` cover. The relay wakes a Bot with `hermes -p <profile> chat --in ~ -c "Bot Chat" -Q --query-file -`,
the new messages on stdin, in its workspace. Agents on hosted platforms are woken by the server (`cloud/src/wake/`):
after `room say` pushes to a hosted Base, the CLI posts `{room, file}` to `/api/bases/:id/rooms/posted` (a token
that can write the Base; 202, and a failure only prints a line). In the background the server reads that message
from the repository (`Repos.readFile`, so an announcement can't invent one) and records it in `room_posts`, the
brake's history. Then it calls each of the Base owner's wake targets (`wake_targets`, one per name in rooms per
user, not tied to a token: platform, name, address, sealed key) whose name has a member file in the room and isn't
the author. It applies the brake (the last 10 recorded posts all by members) and 20 wakes an hour, tries each
call 3 times (after 2 s and 8 s), and shows the result on the dashboard. Keys are sealed with AES-GCM under a key
derived from `BETTER_AUTH_SECRET` (HKDF). A platform is one module implementing `WakePlatform.deliver`;
`grok-bot.ts` POSTs the routine's address with the key as a Bearer token and the event as JSON: Base, room, message
excerpt, agent, and `read` and `reply` commands quoted for the shell. The dashboard lists them under "Woken when
someone posts" on the Agents page (`/agents/wake/new`, `/agents/wake/:id`; migration `0002_wake-targets-by-name`
moved the token-keyed rows over, newest per name) and has a Grok Bot setup prompt on Connect an agent. `room wait`, `room watch` and the relay share
`hostedId` and `whenPushed` in `room-store.mjs`.

**Formatting bar (2026-11-08).** In Edit mode, selecting text shows a bar of format buttons above it, on Liquid
Glass. The Format menu has the same commands. Each one toggles: it adds the Markdown markers, or takes them off when
the selection already has the format, and the bar lights up the formats the selection has.

**App icon (2026-11-08).** The Base concept from `../design/logo/2026-11-08-usual-base/`: three slabs centred on
a white 1024 tile, full-bleed, in `App/Assets.xcassets`. macOS 26 rounds it like any icon. The README shows it too.

**Glass window (2026-11-08).** The whole window is frosted glass: the desktop and other windows show through,
blurred, even when the app isn't active. The file tree and the History pane sit straight on it, and the document
on a rounded Liquid Glass card between them; the gaps beside the card resize the panes. The header hides its toolbar
background and shows the shared window material instead.

**File menu (2026-11-08).** The toolbar shows the open file's name as a glass button; its menu renames,
duplicates, shows in Finder, copies the path or moves the file to the Trash.

**History pane (2026-11-08).** A pane on the right (toolbar button, ⌃⌘H) lists the commits that changed the open
file, newest first: who, when, and the commit's first line. A Base that isn't a git repository offers sync instead.

**Local browser review (2026-11-08, Debug only).** `scripts/review.sh` builds an isolated review app and opens
temporary sample notes. `DebugReview` captures its own window and visible AppKit view frames roughly once per
second; a Python standard-library server exposes them on an authenticated loopback URL. The browser displays
semantic HTML targets, a filterable native hierarchy and pause/resume controls. Selecting a target freezes the
preview for Codex Browser comments. Navigate and edit in the native window; browser input forwarding is not
implemented. SwiftUI groups without useful NSViews get small opt-in `reviewElement` markers. No capture runs
without `USUALBASE_REVIEW`, and Release contains no probe. Details and limitations are in the README.

**Git sync (2026-11-06).** A Base can sync with any git repository over HTTPS with a token. The folder is an
ordinary clone (`.git` inside). Sync is opt-in per Base (`usualbase.sync` in the repository's config). There's no
hosted service, account or history view yet.

**Agent skill and setup prompt (2026-11-07).** `skills/usual-base/` teaches agents to find, read, search and
write a Base, how notes render, how sync and conflict copies work, and rooms (`references/rooms.md`, with links
to notes from the Base's root). The one-time setup is in `references/setup.md` (moved out of `SKILL.md`
2026-11-10, a third of what loads every time); `SKILL.md`'s short "Set up" section points there, so the README's
"Set up your agents" prompt still works.

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
- **The Mac app's Base wizard (2026-11-11):** `EnclosingRepositoryTests` (4: a nested Base ignored in the project's
  `info/exclude` with its status clean, an existing ignore rule respected, special characters escaped, no repository
  around). On a scratch Node server with a sandboxed, ad-hoc-signed Debug build driven by `USUALBASE_SETUP` and
  `USUALBASE_TOKEN`, captured with `USUALBASE_REVIEW`: the welcome card, signing in, name, choosing a Base, the place
  step (with a project, and with its folder already taken) and review, in dark mode. Runs to the end: a new Base in
  a project's `base/` (created on the server; the project ignores it and its status stays clean), an existing Base
  into an empty folder (its notes arrive) and into a folder with files (the Base's version stays, the folder's goes to
  a conflict copy, its other file is pushed). Not tried: clicking through it (the open panels, Back, the animations),
  signing in through the browser from the wizard, light mode, the Bases folder chosen for the first time.
- **`init` for a project, and Bases inside projects (2026-11-11):** a 48-check script against the Node server,
  driving the terminal with `expect` and a stand-in `claude`: on an unconnected machine `init` in a git project
  connects, creates a Base in `<project>/base`, adds `/base/` to the project's `.git/info/exclude` (its status
  stays clean) and sets up Claude Code with the plugin in the project only; the new empty Base's first `sync`
  pushes and `room create` from the project root uses the agent's Base. An existing Base goes into a typed nested
  folder of a plain folder with its notes, tracking `origin/main`; offered folders that can't work are left out
  (a folder holding a repository); a tracked folder, one inside a Base and a number out of range are explained and
  asked again; "no" at the end and Ctrl-C change nothing; a second run offers the Base's folder inside the project
  first; inside a Base it only offers Claude Code. Without a terminal, flags work as before, now for a nested
  folder too; the served (bundled) CLI has it; `connect` sharing, `clone --all`, `path` and `doctor` still work.
  Deployed to base.usual.dev on 2026-11-11 (`e8b9fcc`, from a clean worktree, no migration): the served CLI has
  the project flow and its help, `init` without a connection says to connect, and `/skill.json` has the new
  search and `init` wording. Not tried: waking from this flow (the relay's own setup is unchanged), a real
  `claude`, Linux.
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
- **Rooms (2026-11-10):** a 31-check script with two agents, each with its own home and clone, passed against a bare
  repository (no server), the Node server and `wrangler dev`: create and list; the first post into an empty room; a
  millisecond file name in the day's folder; `say` refusing (exit 3) and showing the unread message, then posting
  with `seen` set; `read` showing only others' new messages; three quick posts as three files; `--re` and `--json`;
  a reply sorting after a message stamped an hour ahead; a message stamped years back still found as new; only the
  message file committed around other edits; two agents posting at once (both pushed, each sees the other's); `wait`
  waking 217 ms (Node) and 622 ms (Cloudflare, real Artifacts) after the other agent's post returned, and by polling
  elsewhere; `wait` timing out with exit 2; finding the Base, and not taking a project repository for one. The
  earlier 47, 33, 37 and 12 checks still pass. Not deployed yet.
- **Claude Code setup and waking (2026-11-10):** a 36-check script (bare repository, a stand-in for `claude`, the
  relay polling every second) passed: setup writes only the repository root's and a nested repository's local
  settings, keeps their own permissions and hooks, excludes them from git, installs the skill, writes nothing
  global, and changes nothing when run again; the hook speaks for the deepest set-up project and is silent outside;
  join, member files, news before and after reading; `sync -m` commits as the agent; the relay wakes once per
  person's message in the project folder as the agent, in a new session, then resumes it once after two messages
  during a run; not for its own message or a room it isn't in; the loop brake and its lifting; the hourly limit;
  `relay status`; `--remove` keeps a hook still used by another project and otherwise takes it out. On the Node
  server the relay woke on a push event 394 ms after the post. Earlier suites still pass (rooms 31 on plain and
  Node, end-to-end 47, init 33, upkeep 37, no server 12). **A real wake (2026-11-10, with the maintainer's OK):**
  Claude Code 2.1.311, woken by the relay in a throwaway project (polling every 2 s), started 2 s after a person's
  post, read the room, replied in 14 s ("pong — Hello from the Base", `seen` set), read a note by its root path,
  appended a line to it and saved it with `sync -m`; both commits are under the agent's name, and nothing in the
  project changed. Not run: `relay install` (only `--dry-run`), Linux.
- **Hermes setup and waking (2026-11-11):** a 17-check script (a stand-in `hermes`, a fake `~/.hermes` with two
  profiles, the relay polling every second) passed: unknown profiles and `--name` with several Bots refused; `--all`
  registers both with the right workspace; the skill in each profile, kept current by `update`; room commands from
  a workspace speak as its Bot; a person's message wakes only the member Bot, once, with
  `hermes -p alpha chat --in ~ -c "Bot Chat" -Q --query-file -` in its workspace and the messages on stdin; its reply
  posts as the Bot and doesn't wake it; `--remove`. Not run on the Hermes server yet: the maintainer wants it set up
  from base.usual.dev after the deploy.
- **Grok Bot waking (2026-11-11):** a 33-check script (three CLI homes, a local stand-in for the routine) passed on
  the Node server and `wrangler dev`: the form refuses a non-https address, shows where it wakes but never the key,
  and stores the key sealed (`v1:…`, checked on Node). A person's `room say` calls the routine once (829 ms after
  `say` started on Node, 2 s on Cloudflare) with the Bearer key and the event, and its `read` and `reply` commands
  work as given. No call for the Bot's own reply, a room it isn't in, or an announced file that isn't in the Base;
  an announcement without a token is refused. The brake (the Bot's reply and 9 of another member's: 8 calls, then
  none); a routine answering 500 tried three times, 2 s and 8 s apart, shown as HTTP 500; 20 wakes in the hour, then
  none; "Stop waking it". Afterwards rooms 31 (plain and Node), Hermes 17, Claude Code 42 and end-to-end 47 still
  pass, and the relay woke on a push event 196 ms after the post. Deployed to base.usual.dev on 2026-11-11 (migration
  `0001_wake-targets` applied; the served CLI announces posts, and the announce route refuses a request without a
  token). Not tried: a real Grok Bot.
- **Dashboard redesign (2026-11-11):** every page looked at in the Claude app's browser pane on a scratch Node
  server with sample data, before and after: welcome, sign in and up (with an error), Bases (tiles), a Base,
  New Base, Agents, Connect an agent, the token page, Wake an agent, entering and approving a code, Connected,
  and the 404 page, in light and dark, at desktop and phone width (no sideways scrolling). Copy buttons fell back
  to selecting the text there; view transitions are in the stylesheet (`@view-transition` parsed). `npm run
  check` and a Worker dry run pass. Deployed to base.usual.dev on 2026-11-11 (`8d5b391`, from a clean worktree):
  the welcome, sign-in and sign-up pages answer 200 with the new look, signed-out dashboard pages redirect to
  sign-in, the 404 page shows for browsers and plain text for others, and the stylesheet, script, both fonts and
  icons are served from hashed paths with a year's caching (the unhashed path 404s). Not seen: Safari, Firefox, a
  regular browser's clipboard, the signed-in pages on production.
- **Shared connections and waking by name (2026-11-11):** on a scratch Node server with a stand-in routine, a
  second `connect` shared the token without approval; `room list` and `sync -m` without a name refused, and `--as`
  and `USUAL_BASE_NAME` worked. Two Bots sharing the connection were each called with their own key; after `connect
  --again` the old token answered 401 and waking went on, without waking the sender. A duplicate name was refused,
  editing kept the key, delete worked, and an unknown id gave 404. Migration `0002` ran on SQLite with sample rows
  (the newest per name kept) and on local D1. Lingering was tried with a stand-in `loginctl` and the platform faked
  as Linux, not on a real Linux host. Deployed to base.usual.dev on 2026-11-11 (`6cbf7c1`, from a clean worktree;
  migration `0002` applied with no wake targets yet to move; the served CLI and skill hold the change). Not tried: a
  real Grok Bot.
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

- **Browser review:** the isolated signed Debug build launches on sample notes. The HTTP feed returns fresh
  ScreenCaptureKit window captures (no fallback) and a populated native element tree; named toolbar targets have
  the expected sizes/positions and every rectangle lies inside the window. The page was opened in the in-app
  browser and exposed the live image and native targets. No automated browser interaction tests or real comment
  submission were performed. Six HTTP tests cover token/host/origin checks, fixed routes, stale/corrupt captures,
  headers and the lack of a write API. Release builds successfully and its executable has no review-probe symbols
  or capture environment variable. Ctrl-C of the first review run exited its owned sample app normally.
- **Checks:** `scripts/check.sh` passes: swift-format lint, 65 BaseKit tests, six review-server tests and an unsigned macOS build, with
  Xcode 27.1 and the macOS 27 SDK; the deployment target is macOS 26.
- **Sync tests** (two Bases and a bare repository on disk, git CLI as a second opinion): publish byte for byte (BOM
  and CRLF) without `.DS_Store`, pull, clean merge of different lines with straight history and kept authors, the
  remote's version plus a conflict copy for clashing lines, edit-versus-delete keeps the edit, a refused push
  fetches and retries, joining a remote that already has files, a file written mid-sync is never overwritten, and
  existing clones don't sync until connected.
- **HTTPS** (opt-in `GitNetworkTests`, 2026-11-06): fetching a public GitHub repository works through the system's
  TLS, and a refused token is reported as `authenticationFailed`.
- **Sync with a token (opt-in `GitRemoteTests`, 2026-11-08):** both directions, a clash with its conflict copy, a
  refused push that fetches and retries, and a wrong token, all against a private GitHub repository (about 20 s for
  the suite) and a Cloudflare Artifacts repository (about 11 s) with the code unchanged. Artifacts accepts the full
  `…?expires=…` token as the Basic password. Also passed through a git proxy Worker in front of Artifacts.
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
  backdrop blur, and the text views drawing no background.
- **Card, panes and History (2026-11-08):** two `GitHistoryTests` (authors, order, dates, summaries, limit, a deleted
  file). Real window captures of a sample git Base with four authors: both panes open, left pane only in Edit mode,
  and the no-git History state; they match the maintainer's sketch, with no divider lines. Not checked: dragging
  the gaps, the toolbar buttons by mouse, dark mode, a busy desktop behind the glass, and history on a large repo.
- **Editor:** debug snapshots on a sample Base show every span kind, including the properties card, hanging
  indents, quote bars and code blocks, in light and dark mode. Outside edits reload the open file, and opening a
  file leaves its bytes unchanged.
- **Highlighter speed:** a 490 KB Markdown file takes 18 ms in a release build and 53 ms in a debug build.

## Not verified yet

- **The Mac app's hosted Bases:** it builds and passes lint, but signing in, the Base menu, cloning into the chosen
  folder, sync with the account's token and live updates haven't been run in the app. Nor has anyone signed up or
  connected an agent on production yet.
- **Sync with credentials in the app:** the keychain item (including prompts after rebuilds of an ad-hoc-signed
  app) and the setup sheet's flow. The sync itself is verified at the BaseKit level (above).
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
