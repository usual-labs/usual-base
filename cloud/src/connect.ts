// The device flow (RFC 8628 in spirit): a client without a browser session asks for a code, the person
// approves it in the dashboard, and the client's polling then receives a token. Used by `usual connect`
// and by the Mac app's Sign In.

import { and, eq, gt, lt } from "drizzle-orm";
import { connectRequests } from "./db";
import type { Env } from "./env";
import { createToken, randomToken, sha256 } from "./tokens";

const LIFETIME_MS = 10 * 60_000;
const INTERVAL_S = 3;
const CODE_ALPHABET = "BCDFGHJKLMNPQRSTVWXZ";

function userCode(): string {
  const chars = [...crypto.getRandomValues(new Uint8Array(8))].map((b) => CODE_ALPHABET[b % CODE_ALPHABET.length]);
  return `${chars.slice(0, 4).join("")}-${chars.slice(4).join("")}`;
}

export function normalizeCode(code: string): string {
  const letters = code.toUpperCase().replace(/[^A-Z]/g, "");
  return letters.length === 8 ? `${letters.slice(0, 4)}-${letters.slice(4)}` : letters;
}

export async function startConnect(env: Env, clientName: string, kind: "agent" | "device") {
  const deviceCode = randomToken();
  const code = userCode();
  const now = Date.now();
  const database = env.db;
  await database.insert(connectRequests).values({
    deviceHash: await sha256(deviceCode), userCode: code, clientName, kind, createdAt: now, expiresAt: now + LIFETIME_MS,
  });
  // Old requests are only useful until they expire.
  await database.delete(connectRequests).where(lt(connectRequests.expiresAt, now - LIFETIME_MS));
  return {
    device_code: deviceCode,
    user_code: code,
    verification_uri: `${env.BASE_URL}/connect`,
    verification_uri_complete: `${env.BASE_URL}/connect?code=${code}`,
    expires_in: LIFETIME_MS / 1000,
    interval: INTERVAL_S,
  };
}

export type ConnectRequest = typeof connectRequests.$inferSelect;

export async function pendingRequest(env: Env, code: string): Promise<ConnectRequest | null> {
  const row = await env.db.select().from(connectRequests).where(eq(connectRequests.userCode, normalizeCode(code)))
    .get();
  return row && row.status === "pending" && row.expiresAt > Date.now() ? row : null;
}

export async function decide(
  env: Env,
  code: string,
  userId: string,
  decision: { approve: false } | { approve: true; scope: "read" | "write"; allBases: boolean; baseIds: string[] },
): Promise<boolean> {
  const set = decision.approve
    ? { status: "approved" as const, userId, scope: decision.scope, allBases: decision.allBases, baseIds: decision.baseIds }
    : { status: "denied" as const, userId };
  const decided = await env.db.update(connectRequests).set(set).where(and(
    eq(connectRequests.userCode, normalizeCode(code)),
    eq(connectRequests.status, "pending"),
    gt(connectRequests.expiresAt, Date.now()),
  )).returning({ userCode: connectRequests.userCode });
  return decided.length === 1;
}

/** What a polling client gets: still pending, refused, expired, or its token (exactly once). */
export async function pollConnect(env: Env, deviceCode: string) {
  const hash = await sha256(deviceCode);
  const database = env.db;
  const row = await database.select().from(connectRequests).where(eq(connectRequests.deviceHash, hash)).get();
  if (!row || row.status === "used") return { status: "expired" as const };
  if (row.status === "denied") return { status: "denied" as const };
  if (row.expiresAt < Date.now()) return { status: "expired" as const };
  if (row.status === "pending") return { status: "pending" as const, interval: INTERVAL_S };
  // Approved: mark it used first, so two polls can't both get a token.
  const claimed = await database.update(connectRequests).set({ status: "used" })
    .where(and(eq(connectRequests.deviceHash, hash), eq(connectRequests.status, "approved"))).returning().get();
  if (!claimed) return { status: "expired" as const };
  const { id, secret } = await createToken(env, {
    userId: claimed.userId!,
    name: claimed.clientName,
    kind: claimed.kind,
    scope: claimed.scope!,
    allBases: claimed.allBases ?? false,
    baseIds: claimed.baseIds ?? [],
  });
  return { status: "approved" as const, token: secret, token_id: id };
}
