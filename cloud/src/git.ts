// The git endpoint: git smart HTTP for /git/<base>.git, passed to the Base's repository (`env.repos`).
// Clients authenticate with a Usual Base token. Pushes are checked here, the same on every platform: only
// branches, no deletions, fast-forwards only. Accepted pushes are recorded and announced to watching apps.

import { eq } from "drizzle-orm";
import { findBase } from "./bases";
import { bases, pushes } from "./db";
import type { Caller, Env } from "./env";
import { isFastForward, packCommits, readCommands, reportStatus, ZERO_ID } from "./pack";
import { secretFromHeader, tokenCaller } from "./tokens";

const MAX_PUSH_BYTES = 64 * 1024 * 1024; // Artifacts' own limit per push, and a bound on memory elsewhere

const challenge = (message: string) =>
  new Response(message + "\n", { status: 401, headers: { "WWW-Authenticate": 'Basic realm="Usual Base"' } });

export async function handleGit(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const match = url.pathname.match(/^\/git\/([a-z0-9][a-z0-9._-]*)\.git(\/.*)$/);
  if (!match) return new Response("Not found\n", { status: 404 });
  const [, baseId, rest] = match;
  const isPush = rest === "/git-receive-pack" || url.searchParams.get("service") === "git-receive-pack";

  const secret = secretFromHeader(request.headers.get("authorization"));
  if (!secret) return challenge("Sign in with a Usual Base token as the password.");
  const caller = await tokenCaller(env, secret);
  if (!caller) return challenge("This token isn't valid or was revoked.");
  if (!(await findBase(env, caller, baseId))) return new Response("No such Base for this token.\n", { status: 404 });
  if (isPush && !(await findBase(env, caller, baseId, true))) {
    return new Response("This token can read this Base but not push to it.\n", { status: 403 });
  }

  let body: ReadableStream<Uint8Array> | Uint8Array | null = request.body;
  let updates: { oldId: string; newId: string; ref: string }[] = [];
  if (isPush && request.method === "POST") {
    if (request.headers.get("content-encoding")) {
      return new Response("Compressed pushes aren't supported.\n", { status: 415 });
    }
    const length = Number(request.headers.get("content-length") || 0);
    if (length > MAX_PUSH_BYTES) return new Response("A push is limited to 64 MiB.\n", { status: 413 });
    const bytes = new Uint8Array(await request.arrayBuffer());
    if (bytes.length > MAX_PUSH_BYTES) return new Response("A push is limited to 64 MiB.\n", { status: 413 });
    const { commands, packStart, sideband } = readCommands(bytes);
    const refusals = await checkUpdates(env, baseId, commands, bytes.subarray(packStart));
    if (refusals.some((r) => r.error)) {
      return new Response(reportStatus(refusals, sideband), {
        headers: { "content-type": "application/x-git-receive-pack-result", "cache-control": "no-cache" },
      });
    }
    updates = commands;
    body = bytes;
  }

  const response = await env.repos.serve(baseId, {
    method: request.method, path: rest, search: url.search, headers: request.headers, body, write: isPush,
  });
  if (!updates.length || !response.body) return new Response(response.body, response);

  // Pass the result through, and record the push once the server's report says which refs it accepted.
  const [toClient, toRecord] = response.body.tee();
  env.background(recordPush(env, caller, baseId, updates, new Response(toRecord).text()));
  return new Response(toClient, response);
}

async function checkUpdates(
  env: Env,
  baseId: string,
  commands: { oldId: string; newId: string; ref: string }[],
  pack: Uint8Array,
): Promise<{ ref: string; error: string | null }[]> {
  let commits: Map<string, string[]> | null = null;
  const results = [];
  for (const update of commands) {
    let error: string | null = null;
    if (!update.ref.startsWith("refs/heads/")) error = "only branches can be pushed";
    else if (update.newId === ZERO_ID) error = "branches can't be deleted";
    else if (update.oldId !== ZERO_ID) {
      commits ??= (await packCommits(pack)).commits;
      const forward = await isFastForward(update, commits, (start, wanted) => env.repos.contains(baseId, start, wanted));
      if (!forward) error = "not a fast-forward; pull first (force pushes are refused)";
    }
    results.push({ ref: update.ref, error });
  }
  return results;
}

async function recordPush(
  env: Env,
  caller: Caller,
  baseId: string,
  updates: { oldId: string; newId: string; ref: string }[],
  report: Promise<string>,
): Promise<void> {
  const text = await report;
  const accepted = updates.filter((u) => text.includes(`ok ${u.ref}`));
  if (!accepted.length) return;
  const now = Date.now();
  const tokenName = caller.token?.name ?? caller.user.name;
  const database = env.db;
  await database.batch([
    database.insert(pushes).values(accepted.map((u) => ({
      baseId, tokenId: caller.token?.id ?? null, tokenName, ref: u.ref, oldId: u.oldId, newId: u.newId, at: now,
    }))),
    database.update(bases).set({ lastPushAt: now, lastPushBy: tokenName }).where(eq(bases.id, baseId)),
  ]);
  for (const u of accepted) {
    await env.publish({ type: "pushed", base: baseId, ref: u.ref, after: u.newId, by: tokenName, at: now });
  }
}
