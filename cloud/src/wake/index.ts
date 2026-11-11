// Waking agents that live on other platforms (a Grok Bot in Cursor's cloud, say) when someone posts in a room
// they're a member of. The CLI announces each message after pushing it; this checks the message in the Base,
// picks the member agents to wake (never the sender, under the loop brake and an hourly limit) and calls each
// through its platform's module. Agents on the person's own machines are woken by the CLI's relay instead.

import { and, desc, eq, inArray, isNull } from "drizzle-orm";
import { bases, roomPosts, tokenBases, tokens, wakeTargets } from "../db";
import type { Env } from "../env";
import { grokBot } from "./grok-bot";
import type { WakeEvent, WakePlatform } from "./platform";
import { frontMatter, memberPath, MESSAGE_FILE, messagePath, ROOM_NAME } from "./room-files";
import { seal, unseal } from "./secrets";

export const PLATFORMS: Record<string, WakePlatform> = { [grokBot.id]: grokBot };

/** Like the relay: wakes pause once this many messages in a row came from members (agents answering agents). */
export const BRAKE_AFTER = 10;
export const WAKES_PER_HOUR = 20;
const HOUR = 3_600_000;
const RETRY_AFTER_MS = [2_000, 8_000];

export type WakeTarget = Omit<typeof wakeTargets.$inferSelect, "secret">;

export async function wakeTargetOf(env: Env, userId: string, tokenId: string): Promise<WakeTarget | null> {
  const row = await env.db.select().from(wakeTargets)
    .where(and(eq(wakeTargets.userId, userId), eq(wakeTargets.tokenId, tokenId))).get();
  if (!row) return null;
  const { secret: _secret, ...target } = row;
  return target;
}

export async function wakeTargetsOf(env: Env, userId: string): Promise<Record<string, WakeTarget>> {
  const rows = await env.db.select().from(wakeTargets).where(eq(wakeTargets.userId, userId));
  return Object.fromEntries(rows.map(({ secret: _secret, ...target }) => [target.tokenId, target]));
}

/** Sets an agent token's wake target. An empty `secret` keeps the stored one. */
export async function saveWakeTarget(env: Env, userId: string, tokenId: string,
  input: { platform: string; name: string; url: string; secret: string }): Promise<string | null> {
  if (!PLATFORMS[input.platform]) return "Choose how this agent is woken.";
  let url: URL;
  try {
    url = new URL(input.url);
  } catch {
    return "The address isn't a URL.";
  }
  const local = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  if (url.protocol !== "https:" && !(local && url.protocol === "http:")) return "The address must start with https://.";
  const existing = await env.db.select({ secret: wakeTargets.secret }).from(wakeTargets).where(eq(wakeTargets.tokenId, tokenId)).get();
  if (!input.secret && !existing) return "Paste the key too.";
  const secret = input.secret ? await seal(env, input.secret) : existing!.secret;
  const values = { platform: input.platform, name: input.name, url: url.href, secret, lastResult: null };
  await env.db.insert(wakeTargets).values({ tokenId, userId, createdAt: Date.now(), ...values })
    .onConflictDoUpdate({ target: wakeTargets.tokenId, set: values });
  return null;
}

export async function removeWakeTarget(env: Env, userId: string, tokenId: string): Promise<void> {
  await env.db.delete(wakeTargets).where(and(eq(wakeTargets.userId, userId), eq(wakeTargets.tokenId, tokenId)));
}

/** A member file whose name is `name`: the CLI's `room join` wrote it. */
async function isMember(env: Env, baseId: string, room: string, name: string): Promise<boolean> {
  const text = await env.repos.readFile(baseId, memberPath(room, name));
  return text !== null && (frontMatter(text, "name") ?? name) === name;
}

/** After the CLI pushed a message to a room: wakes the room's member agents that have a wake target. */
export async function onRoomPost(env: Env, baseId: string, room: string, file: string): Promise<void> {
  if (!ROOM_NAME.test(room) || !MESSAGE_FILE.test(file)) return;
  const base = await env.db.select({ name: bases.name, ownerId: bases.ownerId }).from(bases).where(eq(bases.id, baseId)).get();
  if (!base) return;
  // Agents of the Base's owner that can be woken, still connected, and whose tokens cover this Base.
  const candidates = await env.db.select({ target: wakeTargets, allBases: tokens.allBases })
    .from(wakeTargets).innerJoin(tokens, eq(tokens.id, wakeTargets.tokenId))
    .where(and(eq(wakeTargets.userId, base.ownerId), isNull(tokens.revokedAt)));
  if (!candidates.length) return;
  const covered = new Set((await env.db.select({ tokenId: tokenBases.tokenId }).from(tokenBases)
    .where(and(eq(tokenBases.baseId, baseId), inArray(tokenBases.tokenId, candidates.map((c) => c.target.tokenId)))))
    .map((r) => r.tokenId));
  const targets = candidates.filter((c) => c.allBases || covered.has(c.target.tokenId)).map((c) => c.target);
  if (!targets.length) return;

  const text = await env.repos.readFile(baseId, messagePath(room, file));
  if (text === null) return; // not pushed, or not a message
  const author = frontMatter(text, "from") || "someone";
  await env.db.insert(roomPosts).values({ baseId, room, file, author, at: Date.now() }).onConflictDoNothing();

  const members = new Map<string, Promise<boolean>>();
  const member = (name: string) => members.get(name) ?? members.set(name, isMember(env, baseId, room, name)).get(name)!;
  const last = await env.db.select({ author: roomPosts.author }).from(roomPosts)
    .where(and(eq(roomPosts.baseId, baseId), eq(roomPosts.room, room))).orderBy(desc(roomPosts.at)).limit(BRAKE_AFTER);
  const braked = last.length === BRAKE_AFTER && (await Promise.all(last.map((r) => member(r.author)))).every(Boolean);

  const body = text.replace(/^---\r?\n[\s\S]*?\r?\n---[ \t]*(\r?\n|$)/, "").trim();
  const now = Date.now();
  for (const target of targets) {
    if (target.name === author || !(await member(target.name))) continue;
    if (braked) {
      await note(env, target.tokenId, `not woken: the last ${BRAKE_AFTER} messages in ${room} came from agents (loop brake)`);
      continue;
    }
    const recent = target.recentWakes.filter((at) => now - at < HOUR);
    if (recent.length >= WAKES_PER_HOUR) {
      await note(env, target.tokenId, `not woken: ${WAKES_PER_HOUR} wakes in the last hour`);
      continue;
    }
    await env.db.update(wakeTargets).set({ recentWakes: [...recent, now], lastWakeAt: now }).where(eq(wakeTargets.tokenId, target.tokenId));
    const event: WakeEvent = {
      type: "usual-base.room.message",
      base: { id: baseId, name: base.name },
      room,
      message: { file, from: author, at: frontMatter(text, "at") ?? "", excerpt: body.slice(0, 500) },
      agent: target.name,
      read: `usual-base room read ${shell(room)} --as ${shell(target.name)} --base ${shell(base.name)}`,
      reply: `usual-base room say ${shell(room)} '<your message>' --as ${shell(target.name)} --base ${shell(base.name)}`,
    };
    env.background(deliver(env, target, event));
  }
}

/** Quoted for a POSIX shell, since the agent runs these commands: names are the person's, but may hold `$` or quotes. */
const shell = (value: string) => `'${value.replaceAll("'", `'\\''`)}'`;

const note = (env: Env, tokenId: string, result: string) =>
  env.db.update(wakeTargets).set({ lastResult: result }).where(eq(wakeTargets.tokenId, tokenId));

/** Calls the platform, trying twice more when it fails. */
async function deliver(env: Env, target: WakeTarget, event: WakeEvent): Promise<void> {
  const platform = PLATFORMS[target.platform];
  const row = await env.db.select({ secret: wakeTargets.secret }).from(wakeTargets).where(eq(wakeTargets.tokenId, target.tokenId)).get();
  if (!platform || !row) return;
  let result = "";
  try {
    const secret = await unseal(env, row.secret);
    for (let attempt = 0; attempt <= RETRY_AFTER_MS.length; attempt++) {
      if (attempt) await new Promise((wait) => setTimeout(wait, RETRY_AFTER_MS[attempt - 1]));
      result = await platform.deliver({ url: target.url, secret }, event).catch((error: Error) => `failed: ${error.message}`);
      if (result === "ok") break;
    }
  } catch (error) {
    result = `failed: ${(error as Error).message}`;
  }
  await note(env, target.tokenId, result === "ok" ? `woken for a message in ${event.room}` : result);
}
