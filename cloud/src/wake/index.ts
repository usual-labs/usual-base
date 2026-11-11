// Waking agents that live on other platforms (a Grok Bot in Cursor's cloud, say) when someone posts in a room
// they're a member of. The CLI announces each message after pushing it; this checks the message in the Base,
// picks the member agents to wake (never the sender, under the loop brake and an hourly limit) and calls each
// through its platform's module. Agents on the person's own machines are woken by the CLI's relay instead.
// A wake target belongs to the agent's name in rooms, not to a token: Bots on one computer share its token, and an
// agent that connects again (a new token) is still the same member of its rooms. Being a member is the opt-in.

import { and, desc, eq } from "drizzle-orm";
import { bases, roomPosts, wakeTargets } from "../db";
import type { Env } from "../env";
import { randomToken } from "../tokens";
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

type WakeRow = typeof wakeTargets.$inferSelect;
export type WakeTarget = Omit<WakeRow, "secret">;
const withoutSecret = ({ secret: _secret, ...target }: WakeRow): WakeTarget => target;

export async function wakeTargetOf(env: Env, userId: string, id: string): Promise<WakeTarget | null> {
  const row = await env.db.select().from(wakeTargets).where(and(eq(wakeTargets.userId, userId), eq(wakeTargets.id, id))).get();
  return row ? withoutSecret(row) : null;
}

export async function wakeTargetsOf(env: Env, userId: string): Promise<WakeTarget[]> {
  return (await env.db.select().from(wakeTargets).where(eq(wakeTargets.userId, userId)).orderBy(wakeTargets.name))
    .map(withoutSecret);
}

export interface WakeInput {
  platform: string;
  /** The agent's name in rooms. */
  name: string;
  url: string;
  /** Empty keeps the saved one. */
  secret: string;
}

/** Adds an agent to wake (`id` null) or changes one. Returns what's wrong, or null when it's saved. */
export async function saveWakeTarget(env: Env, userId: string, id: string | null, input: WakeInput): Promise<string | null> {
  if (!PLATFORMS[input.platform]) return "Choose how this agent is woken.";
  if (!input.name) return "Give the agent's name in rooms.";
  let url: URL;
  try {
    url = new URL(input.url);
  } catch {
    return "The address isn't a URL.";
  }
  const local = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  if (url.protocol !== "https:" && !(local && url.protocol === "http:")) return "The address must start with https://.";
  const mine = (where: ReturnType<typeof eq>) => env.db.select({ id: wakeTargets.id, secret: wakeTargets.secret })
    .from(wakeTargets).where(and(eq(wakeTargets.userId, userId), where)).get();
  const existing = id ? await mine(eq(wakeTargets.id, id)) : undefined;
  if (id && !existing) return "This agent isn't woken any more.";
  const sameName = await mine(eq(wakeTargets.name, input.name));
  if (sameName && sameName.id !== id) return `“${input.name}” is woken already; change that one on the Agents page.`;
  if (!input.secret && !existing) return "Paste the key too.";
  const secret = input.secret ? await seal(env, input.secret) : existing!.secret;
  const values = { platform: input.platform, name: input.name, url: url.href, secret, lastResult: null };
  if (existing) await env.db.update(wakeTargets).set(values).where(eq(wakeTargets.id, existing.id));
  else await env.db.insert(wakeTargets).values({ id: "wk_" + randomToken(9), userId, createdAt: Date.now(), ...values });
  return null;
}

export async function removeWakeTarget(env: Env, userId: string, id: string): Promise<void> {
  await env.db.delete(wakeTargets).where(and(eq(wakeTargets.userId, userId), eq(wakeTargets.id, id)));
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
  // The Base owner's agents that can be woken; below, only the room's members among them are.
  const targets = await wakeTargetsOf(env, base.ownerId);
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
      await note(env, target.id, `not woken: the last ${BRAKE_AFTER} messages in ${room} came from agents (loop brake)`);
      continue;
    }
    const recent = target.recentWakes.filter((at) => now - at < HOUR);
    if (recent.length >= WAKES_PER_HOUR) {
      await note(env, target.id, `not woken: ${WAKES_PER_HOUR} wakes in the last hour`);
      continue;
    }
    await env.db.update(wakeTargets).set({ recentWakes: [...recent, now], lastWakeAt: now }).where(eq(wakeTargets.id, target.id));
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

const note = (env: Env, id: string, result: string) =>
  env.db.update(wakeTargets).set({ lastResult: result }).where(eq(wakeTargets.id, id));

/** Calls the platform, trying twice more when it fails. */
async function deliver(env: Env, target: WakeTarget, event: WakeEvent): Promise<void> {
  const platform = PLATFORMS[target.platform];
  const row = await env.db.select({ secret: wakeTargets.secret }).from(wakeTargets).where(eq(wakeTargets.id, target.id)).get();
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
  await note(env, target.id, result === "ok" ? `woken for a message in ${event.room}` : result);
}
