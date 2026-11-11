# Usual Base: known issues and traps

## Traps

- **`NavigationSplitView` adds its own sidebar glass, and `HSplitView` draws divider lines** from the top of the
  window to the bottom, across the toolbar. `BaseWindow` uses an `HStack` with transparent outline/scroll/clip
  backgrounds and resizes panes from the gaps beside the card. Real window captures on 2026-11-08 show no extra
  pane glass and no lines.
- **NSToolbar measures a SwiftUI toolbar item once.** When the item's content changes width, SwiftUI resizes its
  hosting view but the toolbar keeps the old slot. `GapView` calls `invalidateIntrinsicContentSize()` on its
  ancestors up to the toolbar's item viewer, and the toolbar measures again; frame captures on 2026-11-08 show the
  switch gliding with the card. An empty toolbar item is at least 44 pt wide.
- **A SwiftUI `Menu` label draws its image before its text**, whatever order the label gives. The file menu puts
  the chevron inside the `Text` so it stays after the name.
- **The toolbar's alignment with the card rests on two measured offsets** (`titleStart`, `buttonsWidth` in
  `BaseWindow`): where macOS puts the title after the sidebar button, and how wide the History/sync/Quick Open
  group is. A new macOS toolbar layout, or another button in that group, needs them measured again in a window
  capture (2026-11-08: within 1 pt at pane widths 220/300 and 240/260, with the gaps inside the items).
- **A width change rewraps the text, so the same scroll offset shows other lines.** Opening or closing a pane
  moved the view by sections in a long note, which reads as a reset. `DocumentTextView` notes the line at the top
  before its width changes and scrolls back to it after (`DocumentTextView+TopLine.swift`), in both TextKit 2 and
  the viewer's TextKit 1. Checked in Edit and View with History toggled on a 79-section note (2026-11-08).
  At the very top the clip view starts above the text view (View's clip has an automatic 44 pt inset), which
  `visibleRect` hides; there it keeps the clip's offset, clamped with `constrainBoundsRect`, or a resize scrolled
  it 22–96 pt down. Checked at the top of notes with and without properties, four toggles each.
- **TextKit 2 doesn't move laid-out text when `textContainerInset` changes.** In Edit mode the properties card
  measured taller after the first layout and covered the first lines, though the inset was right.
  `DocumentTextView` lays out the viewport again whenever it changes the inset.
- **`defaults write` from the agent's shell doesn't reach the Debug app's settings.** The app read nil for a key the
  shell had just written. Pass a setting as a launch argument instead (`UsualBase -historyVisible YES`), but a
  launch argument then wins over everything the app saves for that key; to change it while the app runs, set it
  through `lldb -p <pid>` on `NSUserDefaults.standardUserDefaults` from a launch without the argument.
- **Restarting the review launcher changes its URL.** Each run gets a new port and capability token. Reopen the
  printed URL in the live browser panel after rebuilding/restarting; an old tab cannot reconnect to the new run.
- **Review overlay coordinates must intersect `visibleRect` with `bounds`.** Unclipped AppKit views can report
  a visible rect as large as the window, which made toolbar markers cover the whole preview. `DebugReview`
  intersects both before converting to screen coordinates. ScreenCaptureKit also needs `scalesToFit = true`
  for an explicitly enlarged output; otherwise the image occupied only a quarter of the requested canvas.
  The corrected live feed was checked against the sample window and toolbar frames on 2026-11-08.
- **Review is an AppKit hierarchy, not a complete SwiftUI or document tree.** Some SwiftUI controls are drawn
  inside a single hosting view; opt-in Debug markers name important groups. TextKit paragraphs and individual
  segments are not separate targets. Browser comments require pausing the live frame first; end-to-end comment
  delivery and pointer/keyboard selection in the browser remain unverified by automated tests.
- **`"\r\n"` is one Character in Swift.** `hasSuffix("\n")` is false for a CRLF line, and splitting on `"\n"`
  misses CRLF breaks. Check `unicodeScalars`, or use `NSString` line ranges. Found in front-matter parsing on
  2026-11-06; tests cover it.
- **swift-markdown columns count UTF-8 bytes,** 1-based, with exclusive upper bounds. `SourceMap` converts them to
  UTF-16 for `NSRange`. Line breaks follow cmark: LF, CRLF, or a lone CR.
- **swift-markdown doesn't turn bare `https://…` text into links:** `Document(parsing:)` doesn't enable the GFM
  autolink extension. The highlighter finds bare URLs itself.
- **`NSTextView.layoutManager` switches a view to TextKit 1 for good.** Never read the editor's; use
  `textLayoutManager`. The viewer is TextKit 1 from the start, so it's safe there.
- **Restyling during input-method composition or Writing Tools disturbs them.** The coordinator waits until
  `hasMarkedText()` and `isWritingToolsActive` are both false.
- **Screenshots need Screen Recording permission,** which an agent's shell doesn't have. `screencapture` fails with
  "could not create image". Use the Debug `USUALBASE_SNAPSHOT` hook, which draws the window with `cacheDisplay`.
  For something that happens later, such as a sync, set `USUALBASE_SNAPSHOT_DELAY` and make it happen in that time.
  Native Computer Use captured the running window successfully on 2026-11-08; when available, use its app
  screenshot API. Select the full `.app` path if multiple builds make the name or bundle identifier ambiguous.
  The opt-in Debug browser review uses `SCShareableContent.currentProcess` to capture only its own window;
  that path also produced real WindowServer captures successfully without a permission prompt.
- **`.defaultSize` applies only when no window frame is saved.** The snapshot hook takes a size because a debug
  build keeps the last frame.
- **libgit2 doesn't compile with Clang modules on:** `<search.h>`'s `struct entry` clashes with xdiff's. The
  `Clibgit2` target passes `-fno-modules`.
- **Don't define `GIT_RAND_GETENTROPY` on macOS.** `getentropy` is declared in `<sys/random.h>`, which libgit2
  doesn't include, so the build fails; libgit2's own CMake build doesn't set it on macOS either.
- **Swift can't call variadic C functions** such as `git_libgit2_opts`. `CGitShim` wraps the calls the app needs.
- **libgit2 refuses a commit signature with an empty email.** The app falls back to `user@host` when no email is
  set.
- **Tokens can contain `?`** (Cloudflare Artifacts tokens end in `?expires=…`), and `URLComponents` reads it as the
  start of a query. `RemoteAddress` splits `user:token@` off by hand.
- **A read-only or expired token reads as a network error.** Artifacts answers both with HTTP 403, not 401, so
  libgit2 never asks for credentials again and the sync reports "Couldn't reach the remote: unexpected http status
  code: 403" (seen in `GitRemoteTests`, 2026-11-08). Open: map a 403 to a credentials problem that says the token
  can't push or has expired. (Artifacts does accept the full `…?expires=…` token as the Basic password.)
- **Artifacts refuses a file over 32 MiB without a clear message.** git reports "remote failed to report status".
  A push of more than 50,000 objects fails with "pack offset metadata exceeds memory budget" (both 2026-11-08).
- **The sync's own writes inside `.git` raise FSEvents too.** `BaseModel` ignores paths inside `.git` when deciding
  whether to sync, or every sync would schedule the next one.
- **A plain `NSTextBlock` is almost no width wide**, so its text wraps after every letter. `FullWidthTextBlock`
  fills the space it's in; a 100% width would leave out the block's padding and border.
- **TextKit 1 paints a text block's background over its margins.** Space above a code block went grey. The
  renderer puts the space and list indent on a plain outer block, with the shaded block inside it.
- **`NSTextTable`'s automatic layout gives every column the same width.** The renderer sets each column's width
  from its text, the way a browser does.
- **The debug snapshot doesn't draw translucent controls:** the selected segment of the View/Edit switch comes out
  blank, the sidebar selection black in light mode, and the formatting bar's glass not at all. Bordered button
  styles such as `.accessoryBarAction` and `.glass` don't draw in `cacheDisplay` either, which is one reason the
  bar's buttons are borderless. It doesn't draw the window's glass either. Judge those in the running app, or
  attach `lldb -p <pid> --batch` to the Debug build and print `[[[window contentView] superview]
  _subtreeDescription]` and the layers of the view in question: the window glass is an `NSVisualEffectView`
  whose `CABackdropLayer` is `windowServerAware`.
- **Agents' screenshots:** `screencapture` from the agent's shell fails ("could not create image from window")
  without Screen Recording permission, but in the Claude desktop app the Mac-control `osascript` tool can run it
  (`do shell script "screencapture -x -o -l <window>"`), and that captures the real window, glass included.
  System Events UI scripting from there is refused (no Accessibility permission).
- **Building an SF Symbol image is slow** (about 0.1 ms each). The renderer makes the two task boxes once per render.

## Open

- **One full-check run ended during Swift Testing without an assertion diagnostic (2026-11-08).** The fast
  check and immediate full-check retry both passed all 65 BaseKit tests and six server tests; the retry's app
  build also passed. Cause is unresolved; logs are `build/header-check.log` and `build/header-check-retry.log`.
- **Saving isn't atomic against outside writers:** an agent writing between the check and the write loses that
  write. Committing within seconds narrows how much could be lost; it doesn't close the gap.
- **Safe checkout checks before it writes, not as it writes.** A file written in the milliseconds between libgit2's
  check and its write would be overwritten by the remote's version. Not seen; noted from how libgit2 works.
- **SecureTransport is deprecated and stops at TLS 1.2.** GitHub and Cloudflare accept TLS 1.2 today. If a host
  requires TLS 1.3, libgit2 needs another HTTPS backend (a URLSession transport is the likely fix).
- **A replayed commit keeps its original message** even when the replay turned its change into a conflict copy, so
  "Update Welcome.md" can describe a commit that only added `Welcome (conflict …).md`.
- **Restyling resets the whole document's attributes after each edit.** That's fine on the files measured so far,
  but untested on very large files in the app. Restyling only the changed blocks is listed in the improvement ideas.
- **View mode renders on the main thread.** Typical notes take milliseconds, but a 218 KB note dense with tables
  and code takes about 0.24 s, which shows as a pause when opening or reloading it.
- **Copying task boxes or pictures from View mode** gives an object-replacement character (U+FFFC) in plain text.
- **Cursors over the editor and in the toolbar ignore the usual APIs.** `NSTextView` sets its I-beam on every mouse
  move, which covers cursor rects of its subviews, so `MarkdownTextView` asks the formatting bar for its cursor in
  `mouseMoved`/`cursorUpdate` and sets the I-beam back when the pointer leaves the bar. SwiftUI's `.pointerStyle`
  had no effect on toolbar items, so `hoverHighlight` sets `NSCursor` from `onContinuousHover`. The bar's cursors
  were checked through lldb (2026-11-08); the toolbar's weren't.
- **A Lucide symbol can compile without its images.** SwiftDraw's conversion of `braces` built only as a vector glyph
  in `Assets.car`, with none of the pre-rendered images the others get, and `NSImage(named:)` returned nil, with no
  build warning. After adding symbols, check `xcrun assetutil --info` that each `lucide.*` name has `Image`
  renditions; `braces`, `car`, `plane` and `message-circle` failed this way and were left out (2026-11-08).
- **A borderless `NSButton` clips a Lucide symbol.** Set as the button's `image`, the icons in `IconGridView` lost
  their right and bottom edges; an `NSImageView` inside the button draws them whole (the button keeps clicks
  through `hitTest`). Offscreen renders (`cacheDisplay`) also drop `labelColor` icons, so check such views in a
  real window (2026-11-08).

## Hosted service

- **The Docker image carries drizzle-kit and esbuild (about 50 MB).** Better Auth lists drizzle-kit as an optional
  peer, so npm keeps it, and what it needs, after `npm prune --omit=dev`; `--omit=peer` doesn't drop it either.
  The server never loads them. Also left behind: empty scope folders of pruned packages.
- **`@hono/node-server` types the request's bindings as HTTP/1 or HTTP/2**, so the Node entry casts `incoming` to
  `IncomingMessage`; it only serves HTTP/1.
- **`wrangler dev` rewrites the request URL and `Origin` to the route's host** (`http://base.usual.dev`), even
  with `--env dev`. A CSRF check against `BASE_URL` failed locally; comparing with the request's own origin
  (Hono's default) works locally and in production.
- **Drizzle leaves column names unqualified in a single-table query**, including inside `sql` templates, so a
  correlated subquery's `${tokens.id}` came out as a bare `id` and matched the subquery's own table. Use a join
  (`listTokens` joins and groups) or qualify the column by hand.
- **Migrations start at drizzle-kit's `0000_init.sql`.** It replaced a hand-written `0001_init.sql` on
  2026-11-09, while base.usual.dev's database was still empty: its old tables and `d1_migrations` were dropped and
  the new migration applied. A local database made before that has to be deleted (`.wrangler/state/v3/d1`).
- **The first remote D1 call can fail with code 7403** ("account is not valid or is not authorized"), which stops
  `npm run deploy` before it deploys anything. An immediate retry worked both times it happened (2026-11-09).
- **Right after a deploy, some requests still reach the previous version** for a few seconds. A smoke test that
  checks served file contents can fail once; repeat it before suspecting the build.
- **pako's `Inflate` reads concatenated zlib streams as one**, so it ran past the first object in a git pack.
  `pack.ts` uses pako's low-level `inflate` with `Z_FINISH` and the object's known size to stop exactly.
- **A custom `build.command` makes wrangler watch only `watch_dir`**, so `src` has to be listed, and the embed
  script writes only on a real change, or its own output would set off another build.
- **`git subtree split` writes progress to stderr;** the CLI reads the commit id from stdout alone. It splits in a
  scratch clone, since git won't fetch a commit no ref points at.
- **Artifacts refuses a file over 32 MiB with "remote failed to report status"**, so `usual-base import` checks sizes
  itself; history over 50,000 objects is pushed in halving batches.
- **git's token helper names Node's real path** (`process.execPath`, such as a versioned folder of a Node install),
  so it breaks when that Node moves or is upgraded away: git then asks for a password. `usual-base doctor` finds it
  and `usual-base update` points the helper at the current Node and CLI.
- **`room wait` needs Node.js 22 for live waiting.** It uses the global `WebSocket` (Node 22+) on a hosted Base;
  older Node, other remotes or a dropped socket fall back to polling every 15 seconds.
- **A room's order follows writers' clocks.** File names and `at` come from the writer's machine; a reply is stamped
  at least 1 ms after the newest message its writer had, but two writers who hadn't seen each other's messages sort
  by their own clocks. The CLI finds unread messages through git, so none is missed.
- **Claude Code's local settings count only at the repository root.** A `.claude/settings.local.json` in a subfolder
  isn't read (code.claude.com permissions docs, 2026-11-10), which is why setup writes the root's. The hook command,
  like git's token helper, names Node's real path, so moving Node means running setup again.
- **Room commands pull before they look for the room.** A room someone else just started isn't in the clone until
  then; `read`, `say`, `wait`, `join` and `leave` all pull first.
- **Plugin monitors are experimental.** Not documented: line limits, restarts, and whether a line wakes an idle
  session; an unknown key in `monitors.json` stops the plugin loading. The monitor checks in every minute, and the
  relay treats a project as having an open session only while it does.
- **Only `room say` wakes agents the server wakes.** The server hears of a message from the CLI after its push; a
  message pushed with plain git, or pushed later by `usual-base sync` after `say` couldn't push, isn't announced,
  so a Grok Bot member isn't woken for it.
- **A plain install's credential helper names Node's real path.** `connect`, `clone` and `init` record
  `'<node>' '<cli>' credential` in git's global config, with Node resolved to its real file, so a Node upgrade that
  moves it (a Homebrew `node` upgrade does) breaks git's sign-in until one of those commands or `update` runs
  again. Homebrew installs avoid it through `USUAL_BASE_COMMAND`. Open: a stable launcher for script installs too.
- **`USUALBASE_SNAPSHOT` draws nothing of the card's glass:** a welcome or wizard capture comes out blank white. Use
  `USUALBASE_REVIEW=<folder in the app's container>`; its `snapshot.json` holds a real window capture as a JPEG
  data URL (2026-11-11). A window launched from a shell isn't active, so prominent buttons look gray in it.
- **A Debug run of the wizard to the end remembers its folder** as the last Base in the Debug container's settings,
  like opening any Base does. Launch with `USUALBASE_SETUP=welcome` to see the empty state anyway.
- **A Base inside a project is invisible to project-wide searches.** The project's git ignores it, so `rg` (and
  tools built on it) from the project root skip it; `rg <text> <Base>` and searches inside it work (tried
  2026-11-11). The skill says to search it by path, and the plugin's session start names the path.
- **`usual-base sync` without a folder syncs whatever repository it's in.** From a project with a Base inside,
  `sync -m` would commit and push the project. Agents are told to pass the Base's path; open: make `sync` refuse a
  repository that isn't a Base when an agent's Base is set up there.
- **A Base made from an empty folder had no upstream** (fixed 2026-11-11): the first `usual-base sync` failed with
  "There is no tracking information". `init` now sets `branch.main.remote` and `.merge` before the Base has notes.
- **Dashboard copy buttons need clipboard access.** Where the browser refuses it (the Claude app's browser pane
  did, 2026-11-11), the button selects the text and tries the old copy command instead, then says "Selected" or
  "Copied". Not yet tried in a regular browser on base.usual.dev.
- **Dashboard assets change only through `scripts/embed.mjs`.** `npm run dev`, `build:node`, `check` and the
  deploy run it; a server started from an old `dist/` serves the old look.
- **Revoking a token doesn't stop waking.** Wake targets belong to agent names, not tokens; "Stop waking it" on
  the Agents page stops them. A Bot whose token is revoked is still called and then can't read the room.
- **The first agent on a machine loses its default name when a second connects.** Until then room commands fall
  back to the connection's name; once `agentNames` holds two, every agent outside a set-up project needs `--as` or
  `USUAL_BASE_NAME`, including the first, whose printed instructions didn't mention it. The refusal says so.
- **A connection's dashboard name is the first agent's.** Agents that share it don't rename it, and pushes record
  that name (`pushes.token_name`); commits carry each agent's own name.
- **Lingering is turned on only where logind allows it without a password**, usually a local session or root;
  over SSH `relay install` prints `sudo loginctl enable-linger <user>` instead. Tested with a stand-in `loginctl`,
  not on a real Linux host yet.
- **Saved wake keys depend on `BETTER_AUTH_SECRET`.** Rotating it makes them unreadable; deliveries then fail
  ("failed: …" on the dashboard) until each key is saved again.
- **The hourly wake limit can let one extra through** when two posts arrive at once: both read the target's recent
  wakes before either writes.
- **The served CLI is a bundle, not `cli/usual-base.mjs`.** Compare a downloaded CLI with
  `cloud/src/generated/files.ts` (after `node scripts/embed.mjs`), not with the source files.
