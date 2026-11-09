import { and, desc, eq, inArray, isNull, sql } from "drizzle-orm";
import { bases, tokenBases, tokens, user } from "./db";
import type { Caller, Env } from "./env";

const TOKEN_PREFIX = "ubt_";

export function randomToken(bytes = 32): string {
  const data = crypto.getRandomValues(new Uint8Array(bytes));
  return btoa(String.fromCharCode(...data)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export interface NewToken {
  userId: string;
  name: string;
  kind: "agent" | "device";
  scope: "read" | "write";
  allBases: boolean;
  baseIds: string[];
}

/** Creates a token and returns its secret, which is shown once and never stored. */
export async function createToken(env: Env, spec: NewToken): Promise<{ id: string; secret: string }> {
  const secret = TOKEN_PREFIX + randomToken();
  const id = "tok_" + randomToken(9);
  const database = env.db;
  // A token only ever gets Bases its user owns.
  const owned = spec.allBases || spec.baseIds.length === 0 ? [] : await database.select({ baseId: bases.id })
    .from(bases).where(and(eq(bases.ownerId, spec.userId), inArray(bases.id, spec.baseIds)));
  await database.batch([
    database.insert(tokens).values({
      id, userId: spec.userId, name: spec.name, kind: spec.kind, scope: spec.scope, allBases: spec.allBases,
      hash: await sha256(secret), prefix: secret.slice(0, 10), createdAt: Date.now(),
    }),
    ...(owned.length ? [database.insert(tokenBases).values(owned.map(({ baseId }) => ({ tokenId: id, baseId })))] : []),
  ]);
  return { id, secret };
}

/** The caller behind a token secret, or null if it's unknown or revoked. */
export async function tokenCaller(env: Env, secret: string): Promise<Caller | null> {
  if (!secret.startsWith(TOKEN_PREFIX)) return null;
  const database = env.db;
  const row = await database.select({ token: tokens, user: { id: user.id, name: user.name, email: user.email } })
    .from(tokens).innerJoin(user, eq(user.id, tokens.userId))
    .where(and(eq(tokens.hash, await sha256(secret)), isNull(tokens.revokedAt))).get();
  if (!row) return null;
  const { token } = row;
  const baseIds = token.allBases ? [] : (await database.select({ baseId: tokenBases.baseId }).from(tokenBases)
    .where(eq(tokenBases.tokenId, token.id))).map((r) => r.baseId);
  // Record use at most once a minute, to keep writes down.
  if (!token.lastUsedAt || Date.now() - token.lastUsedAt > 60_000) {
    await database.update(tokens).set({ lastUsedAt: Date.now() }).where(eq(tokens.id, token.id));
  }
  const { id, name, kind, scope, allBases } = token;
  return { user: row.user, token: { id, name, kind, scope, allBases, baseIds } };
}

/** A user's tokens that still work, newest first, with the names of the Bases each may use. */
export function listTokens(env: Env, userId: string) {
  return env.db.select({
    id: tokens.id, name: tokens.name, kind: tokens.kind, scope: tokens.scope, allBases: tokens.allBases,
    prefix: tokens.prefix, createdAt: tokens.createdAt, lastUsedAt: tokens.lastUsedAt,
    baseNames: sql<string | null>`group_concat(${bases.name}, ', ')`,
  }).from(tokens)
    .leftJoin(tokenBases, eq(tokenBases.tokenId, tokens.id))
    .leftJoin(bases, eq(bases.id, tokenBases.baseId))
    .where(and(eq(tokens.userId, userId), isNull(tokens.revokedAt)))
    .groupBy(tokens.id)
    .orderBy(desc(tokens.createdAt));
}

export type TokenListing = Awaited<ReturnType<typeof listTokens>>[number];

export async function revokeToken(env: Env, userId: string, tokenId: string): Promise<void> {
  await env.db.update(tokens).set({ revokedAt: Date.now() })
    .where(and(eq(tokens.id, tokenId), eq(tokens.userId, userId)));
}

/** The token secret in an Authorization header: `Bearer <secret>` or Basic with the secret as password. */
export function secretFromHeader(header: string | null): string | null {
  if (!header) return null;
  if (header.startsWith("Bearer ")) return header.slice(7).trim();
  if (header.startsWith("Basic ")) {
    try {
      const decoded = atob(header.slice(6).trim());
      return decoded.slice(decoded.indexOf(":") + 1);
    } catch {
      return null;
    }
  }
  return null;
}

/** Whether the caller may read, or write, a Base the caller's user owns. */
export function mayUse(caller: Caller, baseId: string, write: boolean): boolean {
  const token = caller.token;
  if (!token) return true; // a person signed in to the dashboard
  if (write && token.scope !== "write") return false;
  return token.allBases || token.baseIds.includes(baseId);
}
