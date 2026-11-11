// The rooms' files and bookkeeping: where the Base and rooms are, reading messages and members, each reader's
// place, and committing and pushing. The commands are in rooms.mjs; the format is the skill's references/rooms.md:
//   Rooms/<room>/ROOM.md
//   Rooms/<room>/members/<name>.md                                     one file per member, so joins never conflict
//   Rooms/<room>/<UTC day>/<UTC time to the millisecond>_<writer>_<random>.md   (front matter: from, at, seen, re)
// Each reader's place is kept in the clone's .git, by reader name, as the commit up to which they had read.

import { existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, statSync, writeFileSync } from "node:fs";
import { hostname } from "node:os";
import { basename, dirname, join, relative, resolve, sep } from "node:path";
import { basesDir, config, fail, git, gitTry, server, shown, token } from "./core.mjs";
import { folderName, syncRepo } from "./bases.mjs";

export const ROOMS = "Rooms";
export const DAY = /^\d{4}-\d{2}-\d{2}$/;

// --- Where: the Base, the room, and who is reading -----------------------------------------------

/** The agent set up for the project the current folder is in (`setup <platform> <folder>`): the deepest one. */
export function agentHere() {
  let here;
  try {
    here = realpathSync(process.cwd());
  } catch {
    return null;
  }
  const inside = (folder) => here === folder || here.startsWith(folder.endsWith(sep) ? folder : folder + sep);
  return (config.agents || []).filter((a) => inside(a.path)).sort((a, b) => b.path.length - a.path.length)[0] || null;
}

/**
 * The Base room commands work in: --base (a folder, or a Base's name or id on this machine), the Base around the
 * current folder (one with rooms, or a hosted clone), the Base of the agent set up for this project, or the only
 * Base on this machine. A project repository that merely contains the current folder isn't taken for a Base.
 */
export function roomsBase(flags) {
  const top = (dir) => {
    const result = gitTry(["-C", dir, "rev-parse", "--show-toplevel"]);
    return result.ok ? result.stdout.trim() : null;
  };
  if (typeof flags.base === "string") {
    if (existsSync(flags.base)) return top(resolve(flags.base)) || fail(`${flags.base} isn't a git repository, so it can't hold rooms.`);
    const found = localBases(flags).find((b) => b.id === flags.base || basename(b.dir) === folderName(flags.base));
    return found?.dir || fail(`No Base called ${flags.base} on this machine. Clone it, or pass its folder with --base.`);
  }
  const here = top(process.cwd());
  if (here && (existsSync(join(here, ROOMS)) || baseId(here))) return here;
  const agent = agentHere();
  if (agent && existsSync(agent.base)) return agent.base;
  const all = localBases(flags);
  if (all.length === 1) return all[0].dir;
  fail(all.length
    ? `Which Base? Pass --base with one of: ${all.map((b) => shown(b.dir)).join(", ")}.`
    : "No Base here. Run this inside a Base, or pass --base <folder>.");
}

export const baseId = (dir) => gitTry(["-C", dir, "config", "--get", "usualbase.base"]).stdout.trim();

/** The Bases on this machine: folders `init` made, and clones in the Bases folder. */
export function localBases(flags) {
  const dirs = new Set(Object.values(config.folders || {}));
  const root = basesDir(flags);
  if (existsSync(root)) {
    for (const entry of readdirSync(root, { withFileTypes: true })) if (entry.isDirectory()) dirs.add(join(root, entry.name));
  }
  return [...dirs].filter((dir) => existsSync(join(dir, ".git"))).map((dir) => ({ dir, id: baseId(dir) }));
}

/**
 * Who is reading and writing: --as, USUAL_BASE_NAME, the agent set up for this project (so a Claude Code session in
 * it speaks as that agent), the name this machine connected with, or git's user name.
 */
export function readerName(base, flags) {
  if (typeof flags.as === "string" && flags.as.trim()) return flags.as.trim();
  return process.env.USUAL_BASE_NAME || agentHere()?.name || config.name ||
    gitTry(["-C", base, "config", "user.name"]).stdout.trim() || `Agent on ${hostname()}`;
}

export function roomNames(base) {
  const dir = join(base, ROOMS);
  if (!existsSync(dir)) return [];
  return readdirSync(dir, { withFileTypes: true }).filter((e) => e.isDirectory() && !e.name.startsWith(".")).map((e) => e.name).sort();
}

/** The room's folder, relative to the Base, by its name (or its folder's name, ignoring case). */
export function roomPath(base, name) {
  if (!name) fail("Name the room.");
  const rooms = roomNames(base);
  const match = rooms.find((r) => r === folderName(name)) || rooms.find((r) => r.toLowerCase() === folderName(name).toLowerCase());
  if (match) return join(ROOMS, match);
  fail(rooms.length
    ? `No room called ${name}. The rooms are: ${rooms.join(", ")}.`
    : `No room called ${name}, and this Base has no rooms yet; \`usual-base room create ${name}\` starts one.`);
}

// --- Messages ------------------------------------------------------------------------------------

/** A room's messages, oldest first, as paths relative to the room: `<day>/<file>`. */
export function messagesIn(base, room) {
  const dir = join(base, room);
  if (!existsSync(dir)) return [];
  const list = [];
  for (const day of readdirSync(dir).filter((d) => DAY.test(d)).sort()) {
    for (const file of readdirSync(join(dir, day)).filter((f) => f.endsWith(".md")).sort()) list.push(`${day}/${file}`);
  }
  return list;
}

export function readMessage(base, room, path) {
  const text = readFileSync(join(base, room, path), "utf8");
  const parts = text.match(/^---\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)([\s\S]*)$/);
  /** @type {Record<string, string>} */
  const fields = {};
  for (const line of parts ? parts[1].split(/\r?\n/) : []) {
    const colon = line.indexOf(":");
    if (colon < 1) continue;
    let value = line.slice(colon + 1).trim();
    if (value.startsWith('"')) {
      try {
        value = JSON.parse(value);
      } catch {}
    }
    fields[line.slice(0, colon).trim()] = value;
  }
  return { file: basename(path), path, from: String(fields.from ?? ""), at: String(fields.at ?? ""),
    seen: String(fields.seen ?? ""), re: String(fields.re ?? ""), body: (parts ? parts[2] : text).trim() };
}


// --- Each reader's place --------------------------------------------------------------------------

export const placesFile = (base) => join(git(["-C", base, "rev-parse", "--absolute-git-dir"]), "usual-base", "rooms.json");

export function places(base) {
  try {
    return JSON.parse(readFileSync(placesFile(base), "utf8"));
  } catch {
    return {};
  }
}

/** Marks everything in the room up to the current commit as read by this reader. */
export function markRead(base, room, reader, all, commit = head(base)) {
  const file = placesFile(base);
  const saved = places(base);
  saved[reader] = { ...saved[reader], [room]: { commit, last: all.length ? basename(all.at(-1)) : "" } };
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(saved, null, 2) + "\n");
}

export const head = (base) => gitTry(["-C", base, "rev-parse", "--verify", "--quiet", "HEAD"]).stdout.trim();

/**
 * The messages from others this reader hasn't read: files added to the room since the commit they had read up to,
 * found through git rather than by name, so a writer with a slow clock can't hide one. Null if they never read it.
 * `placeKey` keeps a separate place under another key: the relay's record of what it has woken the reader for.
 */
export function unread(base, room, reader, placeKey = reader) {
  const all = messagesIn(base, room);
  const place = places(base)[placeKey]?.[room];
  if (!place) return { all, fresh: null };
  let fresh;
  if (place.commit && gitTry(["-C", base, "cat-file", "-e", `${place.commit}^{commit}`]).ok) {
    const added = gitTry(["-C", base, "diff", "--name-only", "--diff-filter=A", "-z", place.commit, "HEAD", "--", room]).stdout;
    const paths = new Set(added.split("\0").filter(Boolean).map((p) => relative(room, p)));
    fresh = all.filter((path) => paths.has(path));
  } else {
    fresh = all.filter((path) => basename(path) > place.last);
  }
  return { all, fresh: fresh.filter((path) => readMessage(base, room, path).from !== reader) };
}

// --- git -------------------------------------------------------------------------------------------

export const hasRemote = (base) => gitTry(["-C", base, "remote"]).stdout.trim() !== "";

/** The Base's id when this clone pushes to this CLI's server and the CLI has a token there; else null. */
export function hostedId(base) {
  const origin = gitTry(["-C", base, "remote", "get-url", "origin"]).stdout.trim();
  const hosted = origin.match(/^(https?:\/\/[^/]+)\/git\/([a-z0-9][a-z0-9._-]*)\.git$/);
  return hosted && hosted[1] === server && token() ? hosted[2] : null;
}

/** Calls `onChange` on every push to the Base: on a hosted Base's push events, or every `seconds` otherwise. */
export function whenPushed(base, seconds, onChange) {
  const id = hostedId(base);
  if (!id || typeof WebSocket !== "function") {
    setInterval(onChange, seconds * 1000);
    return;
  }
  let retry = 1000;
  const connect = () => {
    const socket = new WebSocket(`${server.replace(/^http/, "ws")}/api/bases/${id}/events`, {
      headers: { authorization: `Bearer ${token()}` },
    });
    const keepAlive = setInterval(() => socket.readyState === 1 && socket.send("ping"), 30_000);
    socket.onopen = () => {
      retry = 1000;
      onChange(); // anything pushed while it was away
    };
    socket.onmessage = (event) => event.data !== "pong" && onChange();
    socket.onclose = () => {
      clearInterval(keepAlive);
      setTimeout(connect, (retry = Math.min(retry * 2, 60_000)));
    };
    socket.onerror = () => {};
  };
  connect();
  setInterval(onChange, 5 * 60_000); // a safety net if an event is ever missed
}

/** Brings in others' messages; offline, the room is read as this clone has it. */
export function pull(base) {
  if (!hasRemote(base)) return;
  const result = gitTry(["-C", base, "pull", "--rebase", "--autostash", "--quiet"]);
  if (!result.ok && !/couldn't find remote ref|no such ref|no tracking information/i.test(result.out)) {
    console.error(`Couldn't pull, so newer messages may be missing: ${result.out.trim().split("\n")[0]}`);
  }
}

/** Commits just these files, under the writer's name, and pushes. */
export function post(base, paths, message, writer) {
  git(["-C", base, "add", "--", ...paths]);
  const email = gitTry(["-C", base, "config", "user.email"]).stdout.trim() || `${slug(writer)}@agents.invalid`;
  git(["-C", base, "-c", `user.name=${writer}`, "-c", `user.email=${email}`, "commit", "--quiet", "--no-verify", "-m", message, "--", ...paths]);
  if (!hasRemote(base)) return;
  try {
    syncRepo(base);
  } catch (error) {
    fail(`Saved in this clone, but not pushed yet: ${error.message} \`usual-base sync\` tries again.`);
  }
}

export const slug = (name) =>
  name.toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 32) || "someone";

/** A front matter value, quoted when YAML would otherwise read it as something else. */
export const yaml = (value) =>
  /^[A-Za-z][\w .,()'@/+-]*$/.test(value) && !/^(true|false|yes|no|on|off|null)$/i.test(value) ? value : JSON.stringify(value);

// --- Members and the loop brake ---------------------------------------------------------------------

/** A room's members, from one file each in `members/`: the name in its front matter, or else the file's name. */
export function members(base, room) {
  const dir = join(base, room, "members");
  if (!existsSync(dir)) return [];
  return readdirSync(dir).filter((f) => f.endsWith(".md")).sort().map((file) => {
    const text = readFileSync(join(dir, file), "utf8");
    let name = text.match(/^---\r?\n(?:.*\r?\n)*?name:[ \t]*(.+?)[ \t]*\r?$/m)?.[1] ?? file.slice(0, -3);
    if (name.startsWith('"')) {
      try {
        name = JSON.parse(name);
      } catch {}
    }
    return { name, path: join(room, "members", file) };
  });
}

export const memberPath = (room, name) => join(room, "members", `${slug(name)}.md`);

/** Wakes pause once this many messages in a row came from members (agents answering agents); a person's lifts it. */
export const BRAKE_AFTER = 10;

export function braked(base, room) {
  const names = new Set(members(base, room).map((m) => m.name));
  const last = messagesIn(base, room).slice(-BRAKE_AFTER);
  return last.length === BRAKE_AFTER && last.every((path) => names.has(readMessage(base, room, path).from));
}

/** What's new for this reader in the rooms they're a member of. Marks nothing read. */
export function news(base, reader) {
  const found = [];
  for (const name of roomNames(base)) {
    const room = join(ROOMS, name);
    if (!members(base, room).some((m) => m.name === reader)) continue;
    const { all, fresh } = unread(base, room, reader);
    const list = fresh ?? all.filter((path) => readMessage(base, room, path).from !== reader);
    if (list.length) found.push({ name, room, count: list.length, latest: readMessage(base, room, list.at(-1)), braked: braked(base, room) });
  }
  return found;
}

/** Pulls unless this clone pulled in the last `seconds`, so a hook that runs before every prompt stays quick. */
export function pullAtMostEvery(base, seconds) {
  const stamp = join(dirname(placesFile(base)), "pulled");
  try {
    if (Date.now() - statSync(stamp).mtimeMs < seconds * 1000) return;
  } catch {}
  pull(base);
  mkdirSync(dirname(stamp), { recursive: true });
  writeFileSync(stamp, "");
}
