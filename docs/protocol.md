# The Usual Base server protocol

What the Mac app and the `usual` CLI expect from a Usual Base server. [base.usual.dev](https://base.usual.dev) is
one; its code is in [cloud/](../cloud/README.md), which also runs in Docker. Any server that answers these requests
works with both: point the CLI at it with `USUAL_BASE_SERVER`, and a Debug build of the app with
`USUALBASE_SERVER`.

You don't need a server at all to use Usual Base: the app, the skill and `usual sync` work with any git
repository. A server adds accounts, per-agent tokens, the list of your Bases, and live updates.

## Tokens

Every request except the two connect requests carries a token, which the server issues through the device flow
below:

- **API requests:** `Authorization: Bearer <token>`.
- **git:** the token as the HTTP Basic password, with any user name. A Bearer header works too.

A request without a valid token gets `401`. For git, that response carries `WWW-Authenticate: Basic`, so git asks
its credential helper. A token can be limited to some Bases and to reading: a Base the token can't see is `404`,
and a push with a read-only token is `403`.

## Errors

The JSON API answers errors as `{ "error": "<message for a person>" }` with a 4xx status. Clients show the message
as it is.

## Connecting: the device flow

A client without a browser session gets a token this way, in the spirit of [RFC 8628](https://www.rfc-editor.org/rfc/rfc8628).
These two requests take no token. Their fields are snake_case, as in the RFC.

**`POST /api/connect`** with `{ "name": "Codex on build-box", "kind": "agent" }`. `kind` is `agent` (the CLI)
or `device` (the Mac app). The answer:

```json
{
  "device_code": "<secret the client polls with>",
  "user_code": "BCDF-GHJK",
  "verification_uri": "https://server/connect",
  "verification_uri_complete": "https://server/connect?code=BCDF-GHJK",
  "expires_in": 600,
  "interval": 3
}
```

The client shows `user_code` and opens or prints `verification_uri_complete`. There the person signs in, checks
the code, and chooses which Bases the token covers and whether it can write. That page is the server's own;
clients only link to it.

**`POST /api/connect/token`** with `{ "device_code": "…" }`, every `interval` seconds until it's settled:

| Answer | Meaning |
|---|---|
| `{ "status": "pending", "interval": 3 }` | Not decided yet; ask again. |
| `{ "status": "approved", "token": "…", "token_id": "…" }` | The token, given out once. |
| `{ "status": "denied" }` | The person refused. |
| `{ "status": "expired" }` | Too late, unknown, or already used; start again. |

## Account and Bases

The rest of the API uses camelCase, and times are Unix milliseconds.

- **`GET /api/me`**: `{ "user": { "name", "email" }, "token": { "id", "name", "kind", "scope", "allBases", "baseIds" } }`.
  `scope` is `read` or `write`.
- **`POST /api/token/revoke`**: revokes the token the request was made with (signing out). `{ "revoked": true }`.
- **`GET /api/bases`**: the Bases this token can read, as `{ "bases": [Base] }`.
- **`POST /api/bases`** with `{ "name": "…" }`: creates a Base, `201` with `{ "base": Base }`. Only for a token
  that can write to all Bases, since it then covers the new one too (`403` otherwise).
- **`GET /api/bases/<id>`**: `{ "base": Base, "pushes": [{ "tokenName", "ref", "newId", "at" }] }`, newest push
  first.

A Base:

```json
{
  "id": "notes-k3x9qa",
  "name": "Notes",
  "createdAt": 1794178370353,
  "lastPushAt": 1794178399000,
  "lastPushBy": "Codex on build-box",
  "git": "https://server/git/notes-k3x9qa.git"
}
```

## Git

Each Base is a git repository served over smart HTTP at its `git` address. Clients clone, fetch and push it with
ordinary git (the CLI) or libgit2 (the app), on the `main` branch.

Clients never force-push: when a push is refused, they fetch, rebase and push again. The server should hold every
other git client to the same rule and refuse what would lose someone's work: a push that isn't a fast-forward,
deleting a branch, and pushing anything other than a branch.

## Live updates

**`GET /api/bases/<id>/events`** upgrades to a WebSocket (with the token in the `Authorization` header). After
every accepted push the server sends:

```json
{ "type": "pushed", "base": "notes-k3x9qa", "ref": "refs/heads/main", "after": "<new commit id>", "by": "Codex on build-box", "at": 1794178399000 }
```

The app sends the text `ping` every 30 seconds and the server answers `pong`. While the socket is open, the app
fetches when an event arrives instead of polling every minute. A server without this endpoint still works; the
app keeps polling.

## Optional

- **`GET /skill.json`**: `{ "files": { "SKILL.md": "…", "references/sync.md": "…" } }`, the agent skill, for
  `usual skill` run from a CLI that isn't in a checkout of this repository.
- **`GET /install.sh`** and **`GET /cli/usual.mjs`**: the CLI, set up to talk to this server.
