// Which Claude Code sessions a person has open in a set-up project, and which session last posted in each room,
// so the relay answers in that conversation (resuming it once it's closed) instead of a session of its own.
// Kept by the project's hooks: SessionStart and UserPromptSubmit mark a session open, SessionEnd closes it.

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

/** A session that hasn't sent a prompt for this long counts as closed (it may have crashed without SessionEnd). */
const STALE_MS = 60 * 60_000;

const file = () => join(process.env.XDG_CONFIG_HOME || join(homedir(), ".config"), "usual-base", "claude-sessions.json");

function load() {
  try {
    return JSON.parse(readFileSync(file(), "utf8"));
  } catch {
    return {};
  }
}

function save(all) {
  mkdirSync(dirname(file()), { recursive: true });
  writeFileSync(file(), JSON.stringify(all, null, 2) + "\n");
}

const entry = (all, agent) => (all[agent.path] ??= { open: {}, last: null, rooms: {} });

/** From the hooks: a prompt or start marks the session open and the latest; the end closes it. */
export function noteSession(agent, sessionId, event) {
  if (!sessionId) return;
  const all = load();
  const e = entry(all, agent);
  if (event === "SessionEnd") {
    delete e.open[sessionId];
    if (!Object.keys(e.open).length) delete e.watching; // its monitor stopped with it
  }
  else {
    e.open[sessionId] = Date.now();
    e.last = sessionId;
  }
  save(all);
}

/** From `room say` in a person's session: replies in this room belong to that session. */
export function noteRoomPost(agent, room) {
  const all = load();
  const e = entry(all, agent);
  if (!e.last) return;
  e.rooms[room] = e.last;
  save(all);
}

/** The plugin's monitor checks in while a session runs; a session that stopped checking in is gone. */
const WATCH_MS = 3 * 60_000;

export function noteWatching(agent) {
  const all = load();
  entry(all, agent).watching = Date.now();
  save(all);
}

/** Whether a person has a session open in this agent's project, so its plugin monitor shows every message. */
export function anySessionOpen(agent) {
  const e = load()[agent.path];
  return Boolean(e?.watching && Date.now() - e.watching < WATCH_MS);
}

/** The person's session a room's replies belong to, and whether it's open right now. */
export function roomSession(agent, room) {
  const e = load()[agent.path];
  const id = e?.rooms?.[room];
  if (!id) return null;
  const seen = e.open[id];
  return { id, open: Boolean(seen && Date.now() - seen < STALE_MS) && anySessionOpen(agent) };
}
