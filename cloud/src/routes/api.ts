import { Hono } from "hono";
import { BaseLimitError, cleanName, createBase, findBase, gitURL, listBases, recentPushes } from "../bases";
import { pollConnect, startConnect } from "../connect";
import type { AppEnv } from "../env";
import { revokeToken, secretFromHeader, tokenCaller } from "../tokens";
import { onRoomPost } from "../wake";

/** The JSON API for the CLI and the apps. Every route except /connect takes a token. */
export const api = new Hono<AppEnv>();

api.post("/connect", async (c) => {
  const body = await c.req.json<{ name?: unknown; kind?: unknown }>().catch(() => ({}) as { name?: unknown; kind?: unknown });
  const name = cleanName(body.name) ?? "Unnamed agent";
  const kind = body.kind === "device" ? "device" : "agent";
  return c.json(await startConnect(c.env, name, kind));
});

api.post("/connect/token", async (c) => {
  const body = await c.req.json<{ device_code?: unknown }>().catch(() => ({}) as { device_code?: unknown });
  if (typeof body.device_code !== "string") return c.json({ error: "device_code is required" }, 400);
  c.header("cache-control", "no-store");
  return c.json(await pollConnect(c.env, body.device_code));
});

api.use("*", async (c, next) => {
  const secret = secretFromHeader(c.req.header("authorization") ?? null);
  const caller = secret ? await tokenCaller(c.env, secret) : null;
  if (!caller) return c.json({ error: "A valid Usual Base token is required." }, 401);
  c.set("caller", caller);
  await next();
});

api.get("/me", (c) => {
  const { user, token } = c.get("caller")!;
  return c.json({ user: { name: user.name, email: user.email }, token });
});

/** Revokes the token this request was made with: signing out of an app or the CLI. */
api.post("/token/revoke", async (c) => {
  const { user, token } = c.get("caller")!;
  await revokeToken(c.env, user.id, token!.id);
  return c.json({ revoked: true });
});

api.get("/bases", async (c) => {
  const bases = await listBases(c.env, c.get("caller")!);
  return c.json({ bases: bases.map((base) => ({ ...base, git: gitURL(c.env, base.id) })) });
});

api.post("/bases", async (c) => {
  const caller = c.get("caller")!;
  // Only a token that covers all Bases and can write may add one, since it then covers the new Base too.
  if (caller.token && !(caller.token.allBases && caller.token.scope === "write")) {
    return c.json({ error: "This token can't create Bases; it needs write access to all Bases." }, 403);
  }
  const body = await c.req.json<{ name?: unknown }>().catch(() => ({}) as { name?: unknown });
  const name = cleanName(body.name);
  if (!name) return c.json({ error: "name is required (up to 80 characters)" }, 400);
  try {
    const base = await createBase(c.env, caller.user.id, name);
    return c.json({ base: { ...base, git: gitURL(c.env, base.id) } }, 201);
  } catch (error) {
    if (error instanceof BaseLimitError) return c.json({ error: error.message }, 409);
    throw error;
  }
});

api.get("/bases/:id", async (c) => {
  const base = await findBase(c.env, c.get("caller")!, c.req.param("id"));
  if (!base) return c.json({ error: "No such Base for this token." }, 404);
  return c.json({ base: { ...base, git: gitURL(c.env, base.id) }, pushes: await recentPushes(c.env, base.id) });
});

/** A WebSocket that receives `{ type: "pushed", … }` for every push to the Base. */
api.get("/bases/:id/events", async (c) => {
  const base = await findBase(c.env, c.get("caller")!, c.req.param("id"));
  if (!base) return c.json({ error: "No such Base for this token." }, 404);
  return c.env.watch(base.id, c.req.raw);
});

/**
 * After `usual-base room say` pushed a message: wakes the room's member agents that live on other platforms
 * (src/wake/). Answers at once; the checks and calls run afterwards.
 */
api.post("/bases/:id/rooms/posted", async (c) => {
  const base = await findBase(c.env, c.get("caller")!, c.req.param("id"), true);
  if (!base) return c.json({ error: "No such Base for this token, or it can't write to it." }, 404);
  const body = await c.req.json<{ room?: unknown; file?: unknown }>().catch(() => ({}) as { room?: unknown; file?: unknown });
  if (typeof body.room !== "string" || typeof body.file !== "string") return c.json({ error: "room and file are required" }, 400);
  c.env.background(onRoomPost(c.env, base.id, body.room, body.file));
  return c.json({ accepted: true }, 202);
});
