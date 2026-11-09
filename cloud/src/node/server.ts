// The Node entry point, for running Usual Base yourself (the Dockerfile runs this): a SQLite file for the
// database, bare repositories on disk, live updates from this process, and sign-in limits kept in memory.
// Run the bundle (`npm run build:node`, then `npm start`); it finds `migrations/` next to `dist/`.

import { serve } from "@hono/node-server";
import { createClient } from "@libsql/client";
import { drizzle } from "drizzle-orm/libsql";
import { migrate } from "drizzle-orm/libsql/migrator";
import { mkdirSync } from "node:fs";
import { STATUS_CODES, type IncomingMessage } from "node:http";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { WebSocketServer, type WebSocket } from "ws";
import { app } from "../app";
import { schema, type Database } from "../db";
import type { Env, PushedEvent } from "../env";
import { diskRepos } from "./repos";

function setting(name: string, fallback?: string): string {
  const value = process.env[name] || fallback;
  if (value === undefined) {
    console.error(`${name} isn't set. The settings are in cloud/README.md.`);
    process.exit(1);
  }
  return value;
}

const baseURL = new URL(setting("BASE_URL")).origin;
const secret = setting("BETTER_AUTH_SECRET");
const dataDir = resolve(setting("DATA_DIR", "data"));
const port = Number(setting("PORT", "8080"));
const trustProxy = process.env.TRUST_PROXY === "1";
mkdirSync(dataDir, { recursive: true });

const client = createClient({ url: setting("DATABASE_URL", `file:${join(dataDir, "usual-base.db")}`) });
const libsql = drizzle(client, { schema });
await migrate(libsql, { migrationsFolder: fileURLToPath(new URL("../migrations", import.meta.url)) });
const db: Database = libsql;
const repos = diskRepos(join(dataDir, "repos"));

// --- Live updates: the WebSockets watching each Base ------------------------------------------------

const watchers = new Map<string, Set<WebSocket>>();

async function publish(event: PushedEvent): Promise<void> {
  const message = JSON.stringify(event);
  for (const socket of watchers.get(event.base) ?? []) socket.send(message);
}

function watching(baseId: string, socket: WebSocket) {
  const sockets = watchers.get(baseId) ?? new Set();
  watchers.set(baseId, sockets.add(socket));
  socket.on("message", (data) => {
    if (data.toString() === "ping") socket.send("pong");
  });
  socket.on("close", () => {
    sockets.delete(socket);
    if (!sockets.size) watchers.delete(baseId);
  });
}

// --- Sign-in attempts: 10 a minute per client --------------------------------------------------------

const attempts = new Map<string, { count: number; until: number }>();

function allow(key: string): boolean {
  const now = Date.now();
  const entry = attempts.get(key);
  if (entry && entry.until > now) return ++entry.count <= 10;
  if (attempts.size > 10_000) for (const [k, e] of attempts) if (e.until <= now) attempts.delete(k);
  attempts.set(key, { count: 1, until: now + 60_000 });
  return true;
}

/** The client's address: the socket's, or with TRUST_PROXY=1 the one the proxy in front added last. */
function clientAddress(incoming: IncomingMessage): string {
  const forwarded = trustProxy ? String(incoming.headers["x-forwarded-for"] ?? "").split(",").pop()?.trim() : "";
  return forwarded || incoming.socket.remoteAddress || "unknown";
}

// --- Requests ---------------------------------------------------------------------------------------

function envFor(incoming: IncomingMessage, watch: Env["watch"]): Env {
  return {
    BASE_URL: baseURL,
    BETTER_AUTH_SECRET: secret,
    SIGNUPS: process.env.SIGNUPS,
    db,
    repos,
    publish,
    watch,
    allowAttempt: async () => allow(clientAddress(incoming)),
    background: (work) => void work.catch((error) => console.error(error)),
  };
}

/** The request as addressed to BASE_URL, so the dashboard's origin check holds behind a proxy doing TLS. */
function atBaseURL(path: string, init: RequestInit): Request {
  return new Request(baseURL + path, { ...init, duplex: "half" } as RequestInit);
}

const plainRequest: Env["watch"] = async () => new Response("Expected a WebSocket\n", { status: 426 });

const server = serve({
  port,
  fetch(request, { incoming }) {
    const url = new URL(request.url);
    const body = request.method === "GET" || request.method === "HEAD" ? null : request.body;
    const forwarded = atBaseURL(url.pathname + url.search, { method: request.method, headers: request.headers, body });
    return app.fetch(forwarded, envFor(incoming as IncomingMessage, plainRequest));
  },
});

// A WebSocket request goes through the app like any other, so the token and the Base are checked the same
// way; the events route then calls `watch`, which marks the request to be upgraded.
const sockets = new WebSocketServer({ noServer: true });
server.on("upgrade", async (incoming: IncomingMessage, socket, head: Buffer) => {
  const upgrade = { baseId: "" };
  const watch: Env["watch"] = async (baseId) => {
    upgrade.baseId = baseId;
    return new Response(null, { status: 204 });
  };
  const headers = new Headers();
  for (let i = 0; i < incoming.rawHeaders.length; i += 2) headers.append(incoming.rawHeaders[i], incoming.rawHeaders[i + 1]);
  const response = await Promise.resolve(app.fetch(atBaseURL(incoming.url ?? "/", { headers }), envFor(incoming, watch)))
    .catch((error) => {
      console.error(error);
      return new Response(null, { status: 500 });
    });
  if (!upgrade.baseId) {
    socket.end(`HTTP/1.1 ${response.status} ${STATUS_CODES[response.status] ?? ""}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`);
    return;
  }
  sockets.handleUpgrade(incoming, socket, head, (ws) => watching(upgrade.baseId, ws));
});

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => {
    for (const ws of sockets.clients) ws.close(1001, "server stopping");
    server.close(() => process.exit(0));
  });
}

console.log(`Usual Base at ${baseURL}, listening on port ${port}, data in ${dataDir}`);
