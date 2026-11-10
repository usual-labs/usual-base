# Usual Base: known issues and traps

## Traps

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
