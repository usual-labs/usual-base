`docs/agents/` holds what the code can't show; code is the source of truth.

## What Usual Base won't compromise on

- **Lossless files.** Agents read these files byte for byte. The app never rewrites text nobody edited: front
  matter, line endings and a byte-order mark pass through untouched, and the editor holds plain text only.
- **Never lose a change.** A save that would overwrite a change made on disk goes to a conflict copy instead.
- **Native and light.** SwiftUI and AppKit, no web views: the editor on TextKit 2, the viewer on TextKit 1 for its
  text tables. Dependencies stay few and well maintained: swift-markdown, Yams, and libgit2 built from vendored
  source.
- **Sync is opt-in.** A Base syncs only after someone connects it; a repository opened as a Base never starts
  committing and pushing on its own.
- **Plain.** Text in the app says what happened and what to do next.

## Ways to hurt yourself

1. **Touching the editor's `layoutManager`.** Reading `NSTextView.layoutManager` switches that view to TextKit 1
   for good, silently. That breaks the editor's block drawing and inline Writing Tools. The viewer is TextKit 1 on
   purpose, from the start.
2. **Pointing a debug build at real notes.** It saves edits, and in a connected Base it commits and pushes them.
   Use a sample folder with a bare repository on disk as its remote (see the README's debug launch settings), not
   your own Base.
3. **Stopping the wrong process.** Stop only a PID you captured when you started it. The developer may be running
   the app.

## Verifying

- Run `scripts/check.sh --fast` while you work and `scripts/check.sh` before you hand work over.
- A logic bug gets a BaseKit test that fails first. Text and offset bugs usually need CRLF and multi-byte cases.
  Sync bugs get a `GitSyncTests` case: two Bases and a bare repository in a temporary folder.
- `USUALBASE_NETWORK_TESTS=1` adds the tests that reach GitHub over HTTPS.
- To see the app, launch a Debug build with `USUALBASE_OPEN`, `USUALBASE_FILE`, `USUALBASE_MODE` and
  `USUALBASE_SNAPSHOT` (README); `USUALBASE_SELECT` selects text, which shows the formatting bar. The snapshot is
  how an agent sees the window without Screen Recording permission; it doesn't draw translucent controls (known
  issues).

## Knowledge index

- [01-overview.md](docs/agents/01-overview.md): what's built, how the pieces fit, and what has been verified.
- [decisions.md](docs/agents/decisions.md): design decisions and their reasons.
- [known-issues.md](docs/agents/known-issues.md): traps found while building, and open problems.
- [improvement-ideas.md](docs/agents/improvement-ideas.md): deferred work.

## Documentation placement

- **The rule, whenever you write docs:** if it's solely about the Usual Base software, it goes in this repository;
  otherwise it goes in the root Usual folder.
- **In this repository:** implementation, architecture, behaviour, setup, testing and technical decisions.
- **In the parent Usual workspace** (`../docs/agents/usual-base.md`): product plans, the hosted service, pricing,
  research and other private decisions. This repository is public on GitHub as `usual-labs/usual-base`.

## Documentation

- **`skills/usual-base/` is the agents' manual.** When anything agents rely on changes (which files show, front
  matter, rendering, sync, conflict copies, or a new feature such as rooms), update the skill in the same change.
- Before adding a paragraph, ask what a maintainer would get wrong without it. If the code answers that, leave it
  out.
- Keep decisions and their reasons, traps, and what hasn't been verified. When a decision changes, rewrite the text;
  don't append.
- Keep files below 500 lines where practical. Use YAGNI, and report behaviour or setup changes after
  implementation.
