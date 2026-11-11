# Usual Base server

The Usual Base server: the dashboard, the JSON API for the CLI and the apps, and git for every Base. It
implements the [server protocol](../docs/protocol.md). The app and the CLI also work without it, with any git
repository.

One [Hono](https://hono.dev) app (`src/app.ts`) runs on two platforms:

| | Cloudflare (`src/cloudflare/`) | Node and Docker (`src/node/`) |
|---|---|---|
| Runs | base.usual.dev, as a Worker | anywhere, as one process or container |
| Database | D1 | a SQLite file (libSQL) |
| Repositories | [Artifacts](https://developers.cloudflare.com/artifacts/), one per Base | bare repositories in a folder, served by `git http-backend` |
| Live updates | a Durable Object per Base | WebSockets held by the process |
| Sign-in limit | Workers rate limiting | in memory |

Each entry point builds the `Env` in `src/env.ts` for every request; everything else is shared:

- **People** sign in to the dashboard with email and password ([Better Auth](https://www.better-auth.com)).
- **Records** (accounts, Bases, tokens, pushes) live in SQLite through [Drizzle](https://orm.drizzle.team): one
  schema, `src/db/schema.ts`, and one set of migrations for both platforms. Better Auth uses its Drizzle adapter
  on the same tables.
- **Agents and apps** use their own tokens (`ubt_…`), which the person approves in the dashboard (the device flow
  behind `usual-base connect` and the Mac app's Sign In) or creates there for sandboxes. Only a SHA-256 hash is
  stored. A token covers some Bases or all, read only or read and write, and can be revoked.
- **Git** goes through `/git/<base>.git` (`src/git.ts`): it checks the token, refuses force pushes, branch
  deletions and anything but branches, passes the request to the Base's repository, records who pushed, and
  tells the apps watching.
- **The CLI and the agent skill** (`../cli/`, `../skills/usual-base/`) are served at `/install.sh`,
  `/cli/usual-base.mjs` and `/skill.json`, embedded at build time by `scripts/embed.mjs`, which bundles the CLI's
  modules into the one file people download. The installer adds `ubase` as a link to it.
- **The dashboard** is server-rendered JSX (`src/pages/`, routes in `src/routes/dashboard.tsx`) with no framework.
  Its look is `assets/app.css`, plus `assets/app.js`, which only adds copy buttons and a question before revoking.
  The fonts (Figtree for text, Prociono for the wordmark, as on usual.dev) and the app icon are in `assets/` too.
  `scripts/embed.mjs` embeds them all, served at `/assets/<name>.<hash>.<ext>` with a year's caching, so a change
  gets a new address. Pages move between each other with cross-document view transitions where the browser has
  them, and without motion for people who ask for reduced motion.

## Run it yourself with Docker

Build from the repository root (the image includes `../cli` and `../skills`), then run it with a volume for its
data:

```sh
docker build -f cloud/Dockerfile -t usual-base .
docker run -d --name usual-base -p 8080:8080 -v usual-base-data:/data \
  -e BASE_URL=http://localhost:8080 -e BETTER_AUTH_SECRET="$(openssl rand -hex 32)" -e SIGNUPS=you@example.com \
  usual-base
```

Open `BASE_URL`, create your account, and connect the app (Debug builds: `USUALBASE_SERVER`) and agents
(`USUAL_BASE_SERVER`, or the install command on the dashboard's Connect an agent page).

| Setting | What it is |
|---|---|
| `BASE_URL` | The address people and agents use, such as `https://base.example.com`. Required. Pages, git addresses and the served CLI use it, and form posts must come from it. |
| `BETTER_AUTH_SECRET` | Signs sessions: a random string of 32 or more characters. Required. Keep it the same across restarts, or everyone is signed out. |
| `SIGNUPS` | Who may create an account: `open`, or a comma-separated list of emails. Unset, nobody can. |
| `DATA_DIR` | Where the data goes; `/data` in the image, `./data` otherwise. |
| `DATABASE_URL` | The SQLite database; default `file:$DATA_DIR/usual-base.db`. |
| `PORT` | The port to listen on; 8080. |
| `TRUST_PROXY` | `1` behind one reverse proxy, so sign-in limits count each client by the address the proxy adds to `X-Forwarded-For` rather than by the proxy's own address. |

- **Data:** the database and one bare repository per Base (`$DATA_DIR/repos/<id>.git`). Back up `$DATA_DIR` while
  the server is stopped, or the database with `sqlite3 usual-base.db ".backup …"` and the repositories with git.
- **HTTPS:** put a reverse proxy such as Caddy in front, set `BASE_URL` to its `https://` address, and set
  `TRUST_PROXY=1`. It must pass WebSocket upgrades through for live updates.
- **Migrations** run when the server starts.
- **Without Docker:** Node 22 and git. `npm ci && npm run build:node`, then `npm start` with the settings above.

## Develop

Node 22, git, and for the Cloudflare version an account on Workers Paid (Artifacts needs it).

```sh
npm install
npm run check                    # embeds files, typechecks both platforms, runs the unit tests

# Cloudflare
cp .dev.vars.example .dev.vars   # then set BETTER_AUTH_SECRET to a random string
npm run dev                      # http://localhost:8799, local D1, Artifacts namespace usual-base-dev

# Node
npm run build:node
BASE_URL=http://localhost:8800 PORT=8800 BETTER_AUTH_SECRET=… SIGNUPS=open npm start
```

`wrangler dev` rewrites each request's URL and `Origin` header to the route's host (`base.usual.dev`); the Node
server likewise treats every request as addressed to `BASE_URL`. So the dashboard's form check compares with the
request's own origin. Point the CLI at a local server with `USUAL_BASE_SERVER`, and the Mac app's Debug build with
`USUALBASE_SERVER`.

To change the schema, edit `src/db/schema.ts` and run `npm run db:generate -- --name <what-changed>`. drizzle-kit
writes the next migration to `migrations/` (with its snapshot in `migrations/meta/`, which it needs for the next
diff). Wrangler applies it on Cloudflare (`npm run dev`, `npm run deploy`); the Node server applies it when it
starts. Commit the generated files and don't edit an applied migration.

## Deploy to Cloudflare

```sh
npm run deploy    # applies D1 migrations, then deploys to base.usual.dev
```

Worker secrets (`wrangler secret put <name> --env=""`): `BETTER_AUTH_SECRET` and `SIGNUPS`, as in the table above.

## Limits

- An account can have 50 Bases, a guard against runaway costs rather than a plan.
- A push can be 64 MiB. On Cloudflare, Artifacts' own limits apply too: 50,000 objects per push, 32 MiB per
  file, 1 GB per repository.
- Not built yet: email verification and password reset, billing, sharing a Base with other people, and a web view
  of notes.
