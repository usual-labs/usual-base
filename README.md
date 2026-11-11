<p align="center">
  <img src="App/Assets.xcassets/AppIcon.appiconset/icon-256.png" width="128" height="128" alt="The Usual Base icon: three rounded slabs stacked on one another">
</p>

# Usual Base

A small, native Mac editor for a folder of Markdown files that you and your agents share.

Agents read and write the files directly. The app shows them in a file tree, either rendered for reading or as
Markdown source for editing, with front matter as a properties card. When an agent changes a file, the open document updates. The app never
rewrites text you didn't change.

**Status:** early. It edits a folder on this Mac and syncs it with any git repository over HTTPS. A hosted
service, [base.usual.dev](https://base.usual.dev), is optional and invitation-only for now.

## Install

- **The Mac app** (macOS 26 or later), signed and notarized:

  ```bash
  brew install --cask usual-labs/tap/usual-base
  ```

  Or download `UsualBase-<version>.zip` from the [latest release](https://github.com/usual-labs/usual-base/releases/latest).
- **The `usual-base` CLI for agents** (Node.js 18 or later, and git), with `ubase` as a short name:

  ```bash
  brew install usual-labs/tap/usual-base
  ```

  `brew upgrade usual-labs/tap/usual-base` updates it. Without Homebrew,
  `curl -fsSL https://base.usual.dev/install.sh | sh` installs it in `~/.local/bin`, and `usual-base update` updates
  it.

## What it does

- **Window:** frosted glass. The desktop and windows behind it show through, blurred, even when the app isn't in
  front. The file tree on the left and the History pane on the right sit on the glass, with the document on a
  glass card between them. Drag the gaps beside the card to resize the panes; the toolbar buttons (or ⌃⌘S and ⌃⌘H)
  show and hide them. Turning on Reduce Transparency in System Settings › Accessibility › Display makes the glass
  opaque.
- **Sidebar:** the folders and Markdown files in the Base. Hidden folders, `node_modules`, `.build` and
  `DerivedData` are left out. ⌘P finds a file by name; ⌃⌘S shows or hides the sidebar.
- **Editor:** Apple's text view on TextKit 2, editing the Markdown source. Headings, emphasis, code, quotes, lists,
  tasks, links and tables are styled, and their syntax characters are dimmed.
- **Editing helpers:**
  - Return continues lists, tasks and quotes.
  - Tab and Shift-Tab indent and outdent list items.
  - Selecting text shows a formatting bar above it: bold, italic, strikethrough, code, link, headings, bulleted,
    numbered and task lists, and quotes. Each button adds the format, or takes it off when the selection already
    has it, and lights up when it does. The same commands are in the Format menu (⌘B, ⌘I, ⇧⌘X, ⌘K, and ⌥⌘1 to 3
    and ⌥⌘0 for headings and body text).
  - Pasting a URL over a selection makes a link.
  - Clicking `[ ]` toggles a task.
  - ⌘-click opens a link; links to other Markdown files in the Base open in the app.
- **File menu:** the file's name in the toolbar opens a menu to rename, duplicate, show in Finder, copy the path or
  move the file to the Trash. Renaming doesn't change links to the old name in other notes.
- **History:** for the open file, who changed it and when, newest first, from the Base's git history.
- **View and Edit (⌘E):** one toolbar button switches: a pencil to edit, an eye to view. View shows the file rendered: no Markdown syntax, real tables,
  task boxes, code and quote blocks, rules, and pictures from the Base. A click opens a link, and text can be
  selected, copied and found with ⌘F. Edit shows the Markdown source. The app remembers which one you used last and
  opens in View the first time.
- **Properties:** front matter appears as a card above the text. Edit opens the raw YAML, so formatting and comments
  stay as written.
- **Saving:** changes save shortly after you stop typing, and when you switch files or apps. If the file changed on
  disk while you were editing, your version is saved next to it as `Name (conflict <date>).md`, and the editor shows
  the version on disk.
- **Outside changes:** changes made outside the app appear in the sidebar and in the open document.
- **Sync (optional, per Base):** Sync Settings… connects the Base to a git repository: an HTTPS address and a token
  that can push. The Base folder becomes an ordinary clone, so agents can clone the same repository and read its
  history. Then the app:
  - commits every change in the folder after it has been quiet for 5 seconds, and pushes it
  - fetches every minute and when the app comes to the front, and merges what it finds
  - replays this Mac's commits on top of the remote's, so history stays a straight line and each commit keeps its
    author
  - when the same lines changed on both sides, keeps the remote's version at the path and saves this Mac's as
    `Name (conflict <date>).md`
  - never overwrites a file that changed while it was syncing; it waits and tries again

  The toolbar button shows how syncing is going. Tokens live in the login keychain, not in the repository. A folder
  that is already a git clone only syncs after you turn sync on for it. SSH addresses aren't supported yet.

## Where a Base lives

Pick one per Base; you can move later, since a Base is always just files and git.

- **A folder on this Mac.** Agents on this Mac read and write it directly. Nothing else to set up.
- **Any git repository:** GitHub, GitLab, Forgejo or Gitea, or a bare repository on your own server. Turn on sync
  in the app (above), and agents elsewhere clone the same repository. To host it yourself, run Forgejo or Gitea:
  you get accounts, tokens, protected branches and a web view of the files.
- **A Usual Base server** (optional): an account at base.usual.dev, described next, or the same server run
  yourself in Docker with a SQLite file ([cloud/README.md](cloud/README.md#run-it-yourself-with-docker)).

The `usual-base` CLI helps agents with the first two as well: `usual-base sync` pulls and pushes a clone,
`usual-base import <folder> --to <git url>` pushes an existing knowledge base into an empty repository (`--history`
keeps its git history, even for a subfolder of a bigger repository), and `usual-base skill` installs the agent
skill. Run it from a checkout as `node cli/usual-base.mjs`; it needs Node.js 18+ and git.
**Rooms** are where people and agents talk in a Base: a folder per room under `Rooms/`, one Markdown file per
message in a folder per day, so posting never conflicts and works with any git remote. `usual-base room list |
create | read | say | wait` does the bookkeeping: `say` won't post while there are messages you haven't read, and
shows you them instead; `wait` blocks until someone posts. The format is in the skill's [rooms
reference](skills/usual-base/references/rooms.md). Agents become members with `room join`, and members can be woken
when someone posts: Claude Code and Hermes by a relay on their machine (`usual-base setup claude-code` and
`usual-base setup hermes`), agents on hosted platforms such as a Grok Bot by the server (`cloud/src/wake/`, one
module per platform). See [Set up your agents](#set-up-your-agents).

Installed from a server, it also answers to `ubase`. `usual-base update` keeps it and the installed skill current,
`usual-base doctor` checks the setup and says what to fix, and once a day the commands that work with Bases say when
something is out of date and offer to update.

### Hosted Usual Base

[base.usual.dev](https://base.usual.dev) keeps your Bases for you, so you don't need a git account:

- **Dashboard:** sign in to see your Bases, who last changed each one, and every machine, app and sandbox you
  connected, each with its own token you can revoke (agents on one machine share its connection).
- **Mac app:** with no Base open, the window offers **Create a Base** and **Connect a Base to a folder** (File ›
  New Base… and Connect a Base to a Folder… do the same any time). A short wizard signs this Mac in if needed (you
  approve it in the browser), asks for a name or which Base, then where its folder goes: your Bases folder (chosen
  once, for example `~/Usual Base`), a new folder inside a project, whose git then ignores it, or any folder. It
  changes nothing until you confirm. The menu at the top of the sidebar lists your Bases and opens them from the
  Bases folder. A hosted Base updates the moment anyone pushes, without polling.
- **Agents:** the dashboard's Connect an agent page gives you a prompt to paste. The agent installs the `usual-base`
  CLI and runs `usual-base connect`; you approve it and choose which Bases it may read or write. Cloud sandboxes
  that start fresh each time use a token from the dashboard instead.
- **A Base for a project:** run `usual-base init` in the project's folder. It asks which Base (or makes a new
  one), where its folder goes (inside the project, where Claude Code reads it like any file and the project's git
  ignores it, or with your other Bases) and whether the project's Claude Code uses it, then does it once you agree.
- **Your existing knowledge base:** `usual-base init <folder>` makes the folder itself a Base, where it is, even
  inside a project. It asks which Base, or creates a new one, pushes the folder's files, and from then on
  `usual-base sync` in that folder syncs it. `usual-base import <folder> --name "<name>"` uploads a copy instead,
  with `--history` its git history too, even when it's a subfolder of a bigger repository.

The app and the CLI talk to it through a [small protocol](docs/protocol.md). The server's code is in
[cloud/](cloud/README.md): one Hono app that runs base.usual.dev on Cloudflare, and runs anywhere else on Node or in
Docker, with a SQLite file and plain git repositories.

## Set up your agents

Agents use a Base as plain files, guided by the [Usual Base skill](skills/usual-base/SKILL.md). The skill explains
where things go, how notes render, how sync and conflict copies work, how rooms work, and how to set itself up. It
follows the [Agent Skills](https://agentskills.io) format, so Claude Code, Codex, Cursor and Hermes can load it, and
any other agent can read it as instructions.

Each guide walks through setup, daily use, waking, removal and troubleshooting:

| Agent | What it gets | Woken by new room messages | Guide |
|---|---|---|---|
| Claude Code | The skill, and a plugin on for one project: each session knows who it is and sees new room messages as they arrive. | Yes: a relay on your Mac starts Claude Code in the project when no session is open. | [Claude Code](docs/onboarding/claude-code.md) |
| Hermes | The skill in each Bot's profile, and a name in rooms per Bot. | Yes: a relay where Hermes runs starts a turn in the Bot's Bot Chat. | [Hermes](docs/onboarding/hermes.md) |
| Grok Bot | Your Bases on its computer, the skill, and a routine that answers its rooms. | Yes: base.usual.dev calls the routine. Needs a hosted Base. | [Grok Bot](docs/onboarding/grok-bot.md) |
| Codex, Cursor, OpenCode, OpenClaw, others | The skill and two lines in its global instructions; rooms when you ask. | Not yet. | [Other agents](docs/onboarding/other-agents.md) |
| Cloud sandboxes (Codex cloud, Claude Code on the web) | A token from the dashboard and a setup script. | Not yet. | [Cloud sandboxes](docs/onboarding/other-agents.md#cloud-sandboxes) |

For a hosted Base, the dashboard's **Connect an agent** page has prompts to paste for Claude Code, a Grok Bot and any
other agent, and makes tokens for cloud sandboxes. For a Base on any other git host or a folder on this Mac, fill in
the place in angle brackets and paste this into the agent:

```text
Set up Usual Base for yourself. Usual Base is my shared Markdown knowledge base: I read it in the Usual Base Mac
app, and my agents read and write it as plain files.

- The Base: <the Base's folder on this machine, or its git URL>
- The Usual Base skill: the skills/usual-base folder in https://github.com/usual-labs/usual-base

Read the skill's SKILL.md and follow its "Set up" section: install the skill where you load skills, remember where
the Base is in your global instructions, and check that you can read it. Ask me for anything you need, such as a
token. Don't write anything into the Base yet.
```

The agent installs the skill, adds two lines about the Base to its global instructions, and checks it can read the
Base. For a Base it reaches by git URL, it clones the repository and asks you for a token. Give each agent its own
token where you can, so you can revoke one without the others.

## Requirements

- macOS 26 or later
- Xcode 26 or later

## Build and run

Open `UsualBase.xcodeproj` and run the `UsualBase` scheme. Without a `Config/Local.xcconfig`, builds are signed to
run on this Mac only. To sign with your team, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`.

Checks (formatting, BaseKit and review-server tests, and an unsigned build):

```sh
scripts/check.sh          # everything
scripts/check.sh --fast   # skips the app build
```

The sync tests use a bare repository on disk and need `git` on the `PATH` as a second opinion. Two more tests reach
GitHub over HTTPS and only run when asked:

```sh
USUALBASE_NETWORK_TESTS=1 swift test --package-path Packages/BaseKit --filter GitNetworkTests
```

`GitRemoteTests` sync through a remote that needs a token, such as a private GitHub repository or a Cloudflare
Artifacts repository. Use a scratch repository; the tests push files with unique names to its default branch.
`USUALBASE_TEST_READ_TOKEN`, a read-only token for the same remote, adds a refused-push test:

```sh
USUALBASE_TEST_REMOTE=https://… USUALBASE_TEST_TOKEN=… swift test --package-path Packages/BaseKit --filter GitRemoteTests
```

The app's icons are [Lucide](https://lucide.dev) icons turned into SF Symbols templates, so they follow the text's
size and weight like Apple's. To add one, take its SVG from the `lucide-static` npm package and convert it with
[SwiftDraw](https://github.com/swhitty/SwiftDraw) (`brew install swiftdraw`), keeping the same insets so all icons
share one scale:

```bash
swiftdraw <name>.svg --format sfsymbol --insets 2,2,2,2 --ultralight-stroke-width 50% --output lucide.<name>.svg
```

Put it in `App/Assets.xcassets/Lucide/lucide.<name>.symbolset/` with a `Contents.json` like the others, and use it as
`Image("lucide.<name>")` or `Label(..., image: "lucide.<name>")`. Menus and system dialogs keep Apple's own icons.

libgit2 is compiled from source as part of BaseKit; no Homebrew or CMake is needed. To move to another libgit2
release, run `scripts/vendor-libgit2.sh <tag>` and check the defines in `Packages/BaseKit/Package.swift` against
that release's `src/util/git2_features.h.in`.

### Debug-only launch settings

These environment variables work in Debug builds only:

| Variable | Effect |
|---|---|
| `USUALBASE_OPEN=/path/to/folder` | Opens that folder instead of the last Base. The sandbox only allows a folder inside the app's container, unless you build with `CODE_SIGN_ENTITLEMENTS=` to turn the sandbox off for a local test. |
| `USUALBASE_FILE=relative/path.md` | Opens that file in the Base. |
| `USUALBASE_MODE=view` or `edit` | Opens in that mode. |
| `USUALBASE_SNAPSHOT=/path/shot.png` | Writes a picture of the window to that file shortly after launch, for automated checks that can't take screenshots. |
| `USUALBASE_SNAPSHOT_DELAY` | Seconds to wait before the snapshot. |
| `USUALBASE_SNAPSHOT_SIZE=1100x1300` | Window size for the snapshot. |
| `USUALBASE_SELECT=some text` | Selects the first match in the editor before the snapshot, which shows the formatting bar. Needs `USUALBASE_MODE=edit`. |
| `USUALBASE_SERVER=http://localhost:8799` | Uses that Usual Base server instead of base.usual.dev, such as `npm run dev` in `cloud/`. |
| `USUALBASE_TOKEN=ubt_…` | Starts signed in with that token, for a local server (`USUALBASE_SERVER`); make one with the CLI's `connect` against it. |
| `USUALBASE_SETUP=create` or `connect` | Opens the Base wizard instead of the last Base; `:name`, `:pick`, `:place` or `:review` opens it at that step, and `:run` runs it to the end. `welcome` shows the card with no Base open. Later steps use `USUALBASE_SETUP_BASE` (a Base's name), and `USUALBASE_SETUP_PROJECT` or `USUALBASE_SETUP_FOLDER` for where it goes, inside the app's container. |
| `USUALBASE_REVIEW=/absolute/path` | Writes a live window capture and native view frames to `snapshot.json` in that directory. Use the review launcher below, which creates a private temporary directory and sample Base. |

### Live browser review

```sh
scripts/review.sh
```

Open the printed local URL in Codex's in-app browser. The page follows the running native window about once
a second and overlays selectable elements. Click an element or its entry in the hierarchy to pause the frame;
use the browser's comment tool to annotate it. Each overlay carries the native class, hierarchy and frame.
**Resume live** follows subsequent changes; **Refresh once** updates a paused preview.

Navigate, scroll and edit in the native sample window. This first version does not forward browser input to
the app. It exposes the AppKit view hierarchy, not SwiftUI's private view graph; Debug-only markers name the
mode switch, Quick Open, sync and properties card. A document's text is one native element, not one per paragraph.
Comment delivery is provided by Codex Browser and still needs a human acceptance check.

The launcher needs Python 3 (standard library only), builds a separate `dev.usualbase.review.UsualBase` app with
the sandbox disabled for this local run, and opens disposable notes with no git remote. It uses a random URL on
`127.0.0.1`, checks the HTTP host and origin, and exposes only the viewer assets and capture. Captures are
restricted to this app process. Temporary captures and notes are private to your user; **Ctrl-C** asks only the
review app to quit normally and removes them. Do not use the sample Base for notes you want to keep.

Normal launches do not capture anything. Capture code is compiled out of Release. No new entitlements, packages,
environment variables or deployment steps are needed for ordinary builds; the launcher supplies its Debug
variables. If exact window capture fails, the page labels the fallback as approximate because glass and focus
effects may be missing. A stopped or minimized app becomes stale and disables the live overlay.

The approach was informed by [AppKit Inspector](https://github.com/JaminZhou/AppKitInspector) and
[Build macOS Apps + Browser Mirror](https://github.com/MarcoRossini96/build-macos-apps-browser-mirror).
This implementation uses Apple's AppKit and ScreenCaptureKit APIs directly, with no dependency on either project.

## Layout

- `App/`: the SwiftUI and AppKit app. `App/Editor/` holds the editor's text view, styling and the layout fragment
  that draws code and quote blocks, plus `DocumentTextView`, the column and card layout the editor and viewer share.
  `App/Viewer/` holds View mode's read-only text view.
- `Packages/BaseKit/`: everything that doesn't need a window, with tests:
  - splitting a file into front matter and body
  - reading front matter
  - the Markdown highlighter (Edit mode) and renderer (View mode)
  - the editing helpers
  - the file index and quick-open ranking
  - the folder watcher
  - saving with conflict copies
  - git sync (`Sources/BaseKit/Git/`), on libgit2 from `Vendor/libgit2` and a small C shim (`Sources/CGitShim`)
- `App/Sync/`: the sync controller, its background engine, keychain storage and the sync UI.
- `App/Account/`: signing in to hosted Usual Base, the sidebar's Base menu, clones of hosted Bases and their live
  updates.
- `App/Setup/`: the welcome card with no Base open, and the wizard that creates a Base or connects one to a folder.
- `cloud/`: the Usual Base server, for Cloudflare (base.usual.dev) or Node and Docker ([its README](cloud/README.md)).
- `cli/`: the `usual-base` CLI for agents, `usual-base.mjs` and its modules in `lib/`, with no dependencies (Node.js
  18+ and git). The server serves it bundled into one file.
- `docs/protocol.md`: what the app and the CLI expect from a Usual Base server.
- `docs/onboarding/`: setup guides for each kind of agent, linked from [Set up your agents](#set-up-your-agents).
- `Config/`: build settings and entitlements.
- `skills/usual-base/`: the agent skill. Update it whenever agent-facing behaviour changes.

## Third-party code

- [swift-markdown](https://github.com/swiftlang/swift-markdown): Apache License 2.0. It builds on
  [swift-cmark](https://github.com/swiftlang/swift-cmark) (cmark-gfm), BSD 2-Clause.
- [Yams](https://github.com/jpsim/Yams): MIT. It bundles LibYAML, MIT.
- [libgit2](https://github.com/libgit2/libgit2) 1.9.7, vendored in `Packages/BaseKit/Vendor/libgit2`: GPL 2.0 with a
  linking exception, which allows linking it into any program. Its bundled llhttp (MIT), xdiff (LGPL 2.1) and
  SHA-1 collision detection (MIT) are covered in that folder's `COPYING`.
- The hosted dashboard's fonts, in `cloud/assets/fonts/`: [Figtree](https://github.com/erikdkennedy/figtree) and
  Prociono by Barry Schwartz, both SIL Open Font License 1.1, each license beside its font.

- [Lucide](https://lucide.dev) 1.70.0 icons, as symbols in `App/Assets.xcassets/Lucide`: ISC, with some icons
  derived from Feather (MIT); both notices are in `App/Lucide-LICENSE.txt`, which ships in the app.

## License

Usual Base is released under the [Apache License 2.0](LICENSE). Third-party code keeps its own license, listed
above.
