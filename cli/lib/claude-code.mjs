// Claude Code: `setup claude-code <folder>` makes one project's Claude an agent of a Base, and `hook claude-code`
// is what that project's hooks run. Nothing goes into ~/.claude except the skill.
//
// Claude Code reads .claude/settings.local.json from the git repository's root even when a session starts in a
// subfolder, and not from nested folders' .claude/ (code.claude.com/docs/en/permissions, read 2026-11-10). So the
// hook goes into the repository root's local settings (and each nested repository's), and decides from the folder a
// session starts in which configured project it belongs to: the deepest one above it.

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, resolve, sep } from "node:path";
import { cliFile, config, fail, gitTry, inCheckout, shown, writeConfig } from "./core.mjs";
import { roomsBase } from "./room-store.mjs";
import { noteSession, noteWatching } from "./claude-sessions.mjs";
import { roomActions } from "./rooms.mjs";
import { linkedTo, skillFiles, writeSkill } from "./upkeep.mjs";

const MARK = "hook claude-code";
const SKIPPED = new Set(["node_modules", ".build", "DerivedData", "build", "dist", "Pods", "vendor"]);

/** The agents set up for Claude Code: { platform, path, name, base, wake, claude }. */
export const claudeAgents = () => (config.agents || []).filter((a) => a.platform === "claude-code");

const settingsFile = (root) => join(root, ".claude", "settings.local.json");
const isOurs = (hook) => typeof hook?.command === "string" && hook.command.includes(MARK);

/** The folder whose .claude/settings.local.json Claude Code reads for sessions started in `dir`. */
function settingsRoot(dir) {
  const top = gitTry(["-C", dir, "rev-parse", "--show-toplevel"]);
  return top.ok ? top.stdout.trim() : dir;
}

/** Git repositories nested inside `dir` (not `dir`'s own), a few levels down: each has its own local settings. */
function nestedRoots(dir, depth = 4) {
  const found = [];
  const walk = (folder, level) => {
    if (level > depth) return;
    for (const entry of readdirSync(folder, { withFileTypes: true })) {
      if (!entry.isDirectory() || entry.name.startsWith(".") || SKIPPED.has(entry.name)) continue;
      const child = join(folder, entry.name);
      if (existsSync(join(child, ".git"))) found.push(child);
      walk(child, level + 1);
    }
  };
  walk(dir, 1);
  return found;
}

function readSettings(file) {
  if (!existsSync(file)) return {};
  try {
    return JSON.parse(readFileSync(file, "utf8"));
  } catch {
    fail(`${shown(file)} isn't valid JSON, so it was left alone. Fix it, then run setup again.`);
  }
}

function writeSettings(file, settings) {
  mkdirSync(join(file, ".."), { recursive: true });
  writeFileSync(file, JSON.stringify(settings, null, 2) + "\n");
}

function removeHooks(root) {
  const file = settingsFile(root);
  if (!existsSync(file)) return null;
  const settings = readSettings(file);
  let changed = false;
  for (const [event, groups] of Object.entries(settings.hooks || {})) {
    for (const group of groups) {
      const kept = (group.hooks || []).filter((hook) => !isOurs(hook));
      if (kept.length !== (group.hooks || []).length) changed = true;
      group.hooks = kept;
    }
    settings.hooks[event] = groups.filter((group) => group.hooks.length);
    if (!settings.hooks[event].length) delete settings.hooks[event];
  }
  if (settings.hooks && !Object.keys(settings.hooks).length) delete settings.hooks;
  if (changed) writeSettings(file, settings);
  return changed ? file : null;
}

const inside = (dir, folder) => dir === folder || dir.startsWith(folder.endsWith(sep) ? folder : folder + sep);

/** `usual-base setup claude-code <folder> [--name NAME] [--base BASE] [--wake] [--remove]` */
export async function setupClaudeCode({ args, flags }) {
  const given = args[0] || fail("usual-base setup claude-code <project folder> [--name NAME] [--base BASE] [--wake] [--remove]");
  if (!existsSync(given)) fail(`${given} doesn't exist.`);
  const path = realpathSync(resolve(given));
  const roots = [settingsRoot(path), ...nestedRoots(path)];
  const others = claudeAgents().filter((a) => a.path !== path);

  if (flags.remove) {
    config.agents = (config.agents || []).filter((a) => !(a.platform === "claude-code" && a.path === path));
    writeConfig(config);
    // A repository keeps the plugin while another project in it is still set up.
    const stillUsed = (root) => others.some((a) => inside(a.path, root) || inside(root, a.path));
    const off = roots.filter((root) => !stillUsed(root));
    for (const root of off) {
      removeHooks(root);
      runClaude(["plugin", "uninstall", PLUGIN, "--scope", "local"], root);
    }
    console.log(`Removed the Claude Code setup for ${shown(path)}.${off.length ? ` The plugin is off in: ${off.map(shown).join(", ")}.` : ""}`);
    return;
  }

  const base = roomsBase(flags);
  const name = typeof flags.name === "string" && flags.name.trim() ? flags.name.trim() : `Claude Code in ${basename(path)}`;
  const claude = whichClaude();
  const agent = { platform: "claude-code", path, name, base, wake: Boolean(flags.wake), ...(claude ? { claude } : {}) };
  config.agents = [...(config.agents || []).filter((a) => !(a.platform === "claude-code" && a.path === path)), agent];
  writeConfig(config);

  // Hooks written into local settings by earlier versions: the plugin does their job now.
  roots.forEach(removeHooks);
  const installed = roots.map((root) => installPlugin(root, flags));
  const skillDir = join(homedir(), ".claude", "skills", "usual-base");
  let skillNote;
  if (linkedTo(skillDir)) skillNote = `the skill in ${shown(skillDir)} is a link, so it was left alone`;
  else {
    writeSkill(skillDir, await skillFiles());
    skillNote = `the usual-base skill is in ${shown(skillDir)}`;
  }

  console.log(`${shown(path)} is set up for Claude Code as "${name}", with the Base at ${shown(base)}.`);
  const failed = installed.filter((r) => !r.ok);
  if (failed.length) console.log(`- The Claude Code plugin isn't installed: ${failed[0].error}`);
  else console.log(`- The usual-base Claude Code plugin is on for this project only (${installed.map((r) => shown(r.root)).join(", ")}): a session that starts here hears who it is and what's new, then sees each new message in its rooms as it arrives.`);
  console.log(`- ${skillNote[0].toUpperCase()}${skillNote.slice(1)}.`);
  const nearby = others.filter((a) => roots.some((root) => inside(a.path, root)));
  if (nearby.length) console.log(`- Also set up in this repository: ${nearby.map((a) => `"${a.name}" in ${shown(a.path)}`).join(", ")}. A session belongs to the deepest one above where it starts.`);
  console.log(`- Rooms: the agent joins one with \`usual-base room join <room> --as "${name}" --base "${base}"\`.`);
  if (flags.wake) {
    const { installRelay } = await import("./relay.mjs");
    if (!claude) console.log("- Waking: `claude` isn't on the PATH here, so the relay can't start it. Install Claude Code, then run setup again.");
    else await installRelay(flags);
  } else console.log("- Waking: off. Add --wake to have new messages start Claude when no session is open.");
}

const PLUGIN = "usual-base@usual-labs";

function runClaude(args, cwd) {
  const claude = whichClaude();
  if (!claude) return { ok: false, error: "`claude` isn't on the PATH." };
  const result = spawnSync(claude, args, { cwd, encoding: "utf8" });
  return { ok: result.status === 0, error: (result.stderr || result.stdout || "").trim().split("\n")[0] };
}

/**
 * Installs the plugin for one repository only (`--scope local`, recorded in its untracked local settings). The
 * marketplace is this repository on GitHub, or the checkout the CLI runs from, or --plugin-source.
 */
function installPlugin(root, flags) {
  const source = typeof flags["plugin-source"] === "string" ? flags["plugin-source"]
    : inCheckout() ? resolve(dirname(cliFile()), "..") : "usual-labs/usual-base";
  const added = runClaude(["plugin", "marketplace", "add", source, "--scope", "local"], root);
  if (!added.ok && !/already/i.test(added.error)) return { root, ...added };
  return { root, ...runClaude(["plugin", "install", PLUGIN, "--scope", "local"], root) };
}

/** Claude Code's command on this machine, so the relay can run it with a PATH of its own. */
function whichClaude() {
  if (process.env.USUAL_BASE_CLAUDE) return process.env.USUAL_BASE_CLAUDE;
  for (const dir of (process.env.PATH || "").split(":").filter(Boolean)) {
    const candidate = join(dir, "claude");
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

/** `usual-base hook claude-code`: the project's hooks. Reads the hook's JSON from stdin; never fails a prompt. */
export async function claudeCodeHook(args = []) {
  if (args[1] === "watch") {
    // The plugin's monitor: runs in the session's folder; silent where no project is set up.
    let here;
    try {
      here = realpathSync(process.cwd());
    } catch {
      return;
    }
    const agent = claudeAgents().filter((a) => inside(here, a.path)).sort((a, b) => b.path.length - a.path.length)[0];
    if (!agent || !existsSync(agent.base)) return;
    noteWatching(agent);
    setInterval(() => noteWatching(agent), 60_000);
    await roomActions.watch(agent.base, [], { as: agent.name });
    return;
  }
  try {
    const raw = readFileSync(0, "utf8");
    const input = raw.trim() ? JSON.parse(raw) : {};
    const start = realpathSync(input.cwd || process.cwd());
    const agent = claudeAgents().filter((a) => inside(start, a.path)).sort((a, b) => b.path.length - a.path.length)[0];
    if (!agent || !existsSync(agent.base)) return;
    // The relay's own runs set USUAL_BASE_RELAY: they aren't a person's session.
    if (!process.env.USUAL_BASE_RELAY) noteSession(agent, input.session_id, input.hook_event_name);
    if (input.hook_event_name === "SessionEnd") return;
    await roomActions.news(agent.base, [], { as: agent.name, intro: input.hook_event_name === "SessionStart" });
  } catch (error) {
    console.error(`usual-base hook: ${error.message}`);
  }
}
