import { count, desc, eq, sql } from "drizzle-orm";
import { bases, pushes } from "./db";
import type { Caller, Env } from "./env";
import { mayUse } from "./tokens";

export type Base = Omit<typeof bases.$inferSelect, "ownerId">;

const toBase = ({ ownerId: _, ...base }: typeof bases.$inferSelect): Base => base;

/** A Base's id: its name as a slug plus six random characters, also the Artifacts repo's name. */
export function newBaseId(name: string): string {
  const slug = name.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40)
    || "base";
  const alphabet = "abcdefghijkmnpqrstuvwxyz23456789";
  const suffix = [...crypto.getRandomValues(new Uint8Array(6))].map((b) => alphabet[b % alphabet.length]).join("");
  return `${slug}-${suffix}`;
}

export function cleanName(name: unknown): string | null {
  if (typeof name !== "string") return null;
  const trimmed = name.trim().replace(/\s+/g, " ");
  return trimmed.length >= 1 && trimmed.length <= 80 ? trimmed : null;
}

export async function listBases(env: Env, caller: Caller): Promise<Base[]> {
  const rows = await env.db.select().from(bases).where(eq(bases.ownerId, caller.user.id))
    .orderBy(sql`${bases.name} collate nocase`);
  return rows.filter((row) => mayUse(caller, row.id, false)).map(toBase);
}

/** The Base, if it exists, belongs to the caller's user and the caller may use it this way. */
export async function findBase(env: Env, caller: Caller, id: string, write = false): Promise<Base | null> {
  const row = await env.db.select().from(bases).where(eq(bases.id, id)).get();
  if (!row || row.ownerId !== caller.user.id || !mayUse(caller, id, write)) return null;
  return toBase(row);
}

/** A guard against runaway scripts and storage costs, not a plan limit. */
export const MAX_BASES_PER_USER = 50;

export async function createBase(env: Env, userId: string, name: string): Promise<Base> {
  const database = env.db;
  const owned = await database.select({ n: count() }).from(bases).where(eq(bases.ownerId, userId)).get();
  if ((owned?.n ?? 0) >= MAX_BASES_PER_USER) throw new BaseLimitError();
  const id = newBaseId(name);
  const now = Date.now();
  // The record comes first, so a repository never exists without one; it goes again if creating fails.
  await database.insert(bases).values({ id, ownerId: userId, name, createdAt: now });
  try {
    await env.repos.create(id, name);
  } catch (error) {
    await database.delete(bases).where(eq(bases.id, id));
    throw error;
  }
  return { id, name, createdAt: now, lastPushAt: null, lastPushBy: null };
}

export async function renameBase(env: Env, id: string, name: string): Promise<void> {
  await env.db.update(bases).set({ name }).where(eq(bases.id, id));
}

/** Deletes the repository and every record of the Base. There's no undo. */
export async function deleteBase(env: Env, id: string): Promise<void> {
  await env.repos.delete(id);
  await env.db.delete(bases).where(eq(bases.id, id));
}

export type PushRecord = Awaited<ReturnType<typeof recentPushes>>[number];

export function recentPushes(env: Env, baseId: string, limit = 20) {
  return env.db.select({ tokenName: pushes.tokenName, ref: pushes.ref, newId: pushes.newId, at: pushes.at })
    .from(pushes).where(eq(pushes.baseId, baseId)).orderBy(desc(pushes.at)).limit(limit);
}

export class BaseLimitError extends Error {
  constructor() {
    super(`An account can have up to ${MAX_BASES_PER_USER} Bases.`);
  }
}

/** Git address of a Base. */
export const gitURL = (env: Env, id: string) => `${env.BASE_URL}/git/${id}.git`;
