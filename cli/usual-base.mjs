#!/usr/bin/env node
// Usual Base CLI: syncs a Base with any git repository, imports an existing knowledge base, installs the agent
// skill, and connects to a Usual Base server (base.usual.dev, or one implementing docs/protocol.md).
// One file, no dependencies; needs Node.js 18+ and git.

import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir, hostname, tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";

const VERSION = "0.1.0";
const DEFAULT_SERVER = "https://base.usual.dev";
const MAX_FILE_BYTES = 32 * 1024 * 1024; // Artifacts refuses larger files
const MAX_OBJECTS = 45_000; // Artifacts refuses pushes over 50,000 objects

const configPath = join(process.env.XDG_CONFIG_HOME || join(homedir(), ".config"), "usual-base", "config.json");

function readConfig() {
  try {
    return JSON.parse(readFileSync(configPath, "utf8"));
  } catch {
    return {};
  }
}

function writeConfig(config) {
  mkdirSync(dirname(configPath), { recursive: true });
  writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n", { mode: 0o600 });
  chmodSync(configPath, 0o600);
}

const config = readConfig();
const server = (process.env.USUAL_BASE_SERVER || config.server || DEFAULT_SERVER).replace(/\/$/, "");
const token = () => process.env.USUAL_BASE_TOKEN || config.token;
const basesDir = (flags) =>
  resolve(flags.dir || process.env.USUAL_BASE_DIR || config.dir || join(homedir(), "Usual Base"));

class Failure extends Error {}
const fail = (message) => {
  throw new Failure(message);
};

// --- Arguments ---------------------------------------------------------------------------------

function parse(argv) {
  const args = [];
  const flags = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg.startsWith("--")) {
      const [key, inline] = arg.slice(2).split("=", 2);
      if (inline !== undefined) flags[key] = inline;
      else if (argv[i + 1] !== undefined && !argv[i + 1].startsWith("--") && !["all", "history", "no-clone", "no-skill", "json"].includes(key)) {
        flags[key] = argv[++i];
      } else flags[key] = true;
    } else if (arg === "-m") flags.message = argv[++i];
    else args.push(arg);
  }
  return { args, flags };
}

// --- HTTP --------------------------------------------------------------------------------------

async function call(path, { method = "GET", body, auth = true } = {}) {
  const headers = { "content-type": "application/json", "user-agent": `usual-cli/${VERSION}` };
  if (auth) {
    if (!token()) fail("Not connected. Run `usual-base connect` first, or set USUAL_BASE_TOKEN.");
    headers.authorization = `Bearer ${token()}`;
  }
  const response = await fetch(server + path, { method, headers, body: body && JSON.stringify(body) });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) fail(data.error || `${method} ${path} failed with HTTP ${response.status}`);
  return data;
}

// --- Git ---------------------------------------------------------------------------------------

function git(args, options = {}) {
  return execFileSync("git", args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], ...options }).trim();
}

function gitTry(args, options = {}) {
  const result = spawnSync("git", args, { encoding: "utf8", ...options });
  return { ok: result.status === 0, stdout: result.stdout || "", out: (result.stdout || "") + (result.stderr || "") };
}

/** Makes git ask this CLI for the token whenever it talks to the server, and nothing else. */
function setUpCredentialHelper() {
  const key = `credential.${server}.helper`;
  const command = `!'${process.execPath}' '${resolve(process.argv[1])}' credential`;
  gitTry(["config", "--global", "--unset-all", key]);
  // The empty value first clears helpers set for every host (such as the macOS keychain).
  git(["config", "--global", "--add", key, ""]);
  git(["config", "--global", "--add", key, command]);
}

function folderName(name) {
  return name.replace(/[\/\\:*?"<>|]/g, "-").replace(/^\.+/, "").trim() || "Base";
}

function cloneBase(base, root) {
  const target = join(root, folderName(base.name));
  if (existsSync(join(target, ".git"))) {
    const current = gitTry(["-C", target, "config", "--get", "usualbase.base"]).out.trim();
    if (current === base.id) {
      console.log(`${base.name}: already at ${target}`);
      return target;
    }
    fail(`${target} already holds another repository. Use --dir to clone somewhere else.`);
  }
  mkdirSync(root, { recursive: true });
  const result = gitTry(["clone", "--quiet", base.git, target]);
  if (!result.ok) fail(`Couldn't clone ${base.name}: ${result.out.trim()}`);
  git(["-C", target, "config", "usualbase.base", base.id]);
  console.log(`${base.name}: cloned to ${target}`);
  return target;
}

// --- Commands ----------------------------------------------------------------------------------

const commands = {
  async connect({ flags }) {
    const name = typeof flags.name === "string" ? flags.name : `Agent on ${hostname()}`;
    const start = await call("/api/connect", { method: "POST", body: { name, kind: "agent" }, auth: false });
    console.log(`To connect "${name}", open:\n\n  ${start.verification_uri_complete}\n`);
    console.log(`and check that it shows the code ${start.user_code}. Waiting for approval…`);
    const deadline = Date.now() + start.expires_in * 1000;
    let result;
    while (Date.now() < deadline) {
      await new Promise((done) => setTimeout(done, start.interval * 1000));
      result = await call("/api/connect/token", { method: "POST", body: { device_code: start.device_code }, auth: false });
      if (result.status !== "pending") break;
    }
    if (result?.status === "denied") fail("The connection was denied.");
    if (result?.status !== "approved") fail("The code expired. Run `usual-base connect` again.");
    const dir = basesDir(flags);
    writeConfig({ ...config, server, token: result.token, tokenId: result.token_id, name, dir });
    config.token = result.token;
    setUpCredentialHelper();
    console.log(`\nConnected as "${name}".`);
    if (!flags["no-clone"]) await commands.clone({ args: [], flags: { ...flags, all: true, dir } });
    if (!flags["no-skill"]) await commands.skill({ flags });
    console.log(`
Add these lines to your global instructions (for example ~/.claude/CLAUDE.md or ~/.codex/AGENTS.md):

- Usual Base: ${dir} holds my Bases, git clones of ${server}. Run \`usual-base sync\` in a Base before reading and after committing.
- Use the usual-base skill to look things up there before asking, and to save what should outlast this session.`);
  },

  async whoami() {
    const me = await call("/api/me");
    const t = me.token;
    console.log(`${me.user.name} <${me.user.email}> via "${t.name}" (${t.scope === "write" ? "read and write" : "read only"}, ${t.allBases ? "all Bases" : `${t.baseIds.length} Bases`}) on ${server}`);
  },

  async bases({ flags }) {
    const { bases } = await call("/api/bases");
    if (flags.json) return console.log(JSON.stringify(bases, null, 2));
    if (!bases.length) return console.log("No Bases yet. Create one in the dashboard or with `usual-base import`.");
    for (const base of bases) console.log(`${base.id}\t${base.name}`);
  },

  async clone({ args, flags }) {
    const { bases } = await call("/api/bases");
    const root = basesDir(flags);
    setUpCredentialHelper();
    const chosen = flags.all ? bases : bases.filter((b) => args.includes(b.id) || args.includes(b.name));
    if (!chosen.length) fail(flags.all ? "This token can't read any Bases yet." : "Name a Base (see `usual-base bases`), or use --all.");
    for (const base of chosen) cloneBase(base, root);
  },

  async path({ args, flags }) {
    const { bases } = await call("/api/bases");
    const base = bases.find((b) => b.id === args[0] || b.name === args[0]) || fail(`No Base called ${args[0]}.`);
    console.log(join(basesDir(flags), folderName(base.name)));
  },

  async sync({ args }) {
    const dir = resolve(args[0] || ".");
    const top = gitTry(["-C", dir, "rev-parse", "--show-toplevel"]);
    if (!top.ok) fail(`${dir} isn't a Base clone.`);
    const status = git(["-C", dir, "status", "--porcelain"]);
    if (status) console.log("Uncommitted changes stay local; commit them, then sync again to push them.");
    for (let attempt = 0; attempt < 3; attempt++) {
      const pull = gitTry(["-C", dir, "pull", "--rebase", "--autostash", "--quiet"]);
      if (!pull.ok && !/couldn't find remote ref|no such ref/i.test(pull.out)) fail(`Pull failed: ${pull.out.trim()}`);
      const ahead = gitTry(["-C", dir, "rev-list", "--count", "@{upstream}..HEAD"]);
      const needsPush = !ahead.ok || Number(ahead.out.trim()) > 0;
      if (!needsPush) return console.log("Up to date.");
      const push = gitTry(["-C", dir, "push", "--quiet", "-u", "origin", "HEAD"]);
      if (push.ok) return console.log("Pushed.");
      if (!/rejected|fetch first|stale/i.test(push.out)) fail(`Push failed: ${push.out.trim()}`);
    }
    fail("Others kept pushing; run `usual-base sync` again.");
  },

  async import({ args, flags }) {
    const folder = resolve(args[0] || fail("Name the folder to import: usual-base import <folder> --name <name> | --to <git url>"));
    if (!statSync(folder, { throwIfNoEntry: false })?.isDirectory()) fail(`${folder} isn't a folder.`);
    const name = typeof flags.name === "string" ? flags.name : folder.split("/").pop();
    const work = mkdtempSync(join(tmpdir(), "usual-import-"));
    try {
      const source = flags.history ? historyHead(folder, work) : snapshot(folder, work, name);
      // Any git repository: pushed with git's own credentials, and never over history already there.
      if (typeof flags.to === "string") {
        pushInBatches(source, flags.to);
        return console.log(`Imported into ${withoutCredentials(flags.to)}. Clone it with git, or open the clone in the app.`);
      }
      checkSizes(source);
      const { base } = await call("/api/bases", { method: "POST", body: { name } });
      console.log(`Created Base "${base.name}" (${base.id}). Pushing…`);
      setUpCredentialHelper();
      pushInBatches(source, base.git);
      console.log(`Imported. Clone it with \`usual-base clone ${base.id}\`, or see it at ${server}/bases/${base.id}`);
    } finally {
      rmSync(work, { recursive: true, force: true });
    }
  },

  async skill({ flags }) {
    const files = await skillFiles();
    const home = homedir();
    const targets = typeof flags.to === "string"
      ? [resolve(flags.to)]
      : [
          existsSync(join(home, ".claude")) && join(home, ".claude", "skills", "usual-base"),
          (existsSync(join(home, ".agents")) || existsSync(join(home, ".codex")) || existsSync(join(home, ".cursor"))) &&
            join(home, ".agents", "skills", "usual-base"),
          existsSync(join(home, ".hermes")) && join(home, ".hermes", "skills", "knowledge", "usual-base"),
        ].filter(Boolean);
    if (!targets.length) targets.push(join(home, ".usual-base", "skill"));
    for (const target of targets) {
      for (const [path, text] of Object.entries(files)) {
        mkdirSync(dirname(join(target, path)), { recursive: true });
        writeFileSync(join(target, path), text);
      }
      console.log(`Installed the usual-base skill in ${target}`);
    }
  },

  async logout() {
    writeConfig({ ...config, token: undefined, tokenId: undefined });
    gitTry(["config", "--global", "--unset-all", `credential.${server}.helper`]);
    console.log(`Signed out on this machine. Revoke the token in ${server}/agents to cut it off everywhere.`);
  },

  /** git's credential helper protocol: answers `get` for this server with the token. */
  async credential({ args }) {
    if (args[0] !== "get") return;
    const input = readFileSync(0, "utf8");
    const fields = Object.fromEntries(input.split("\n").filter(Boolean).map((line) => line.split(/=(.*)/s, 2)));
    const wanted = new URL(server);
    if (fields.protocol !== wanted.protocol.slice(0, -1) || fields.host !== wanted.host || !token()) return;
    process.stdout.write(`username=usual\npassword=${token()}\n`);
  },
};

/** The skill's files: the copy beside this CLI in a checkout of the repository, or else the server's. */
async function skillFiles() {
  const local = join(dirname(realpathSync(process.argv[1])), "..", "skills", "usual-base");
  if (!existsSync(join(local, "SKILL.md"))) return (await call("/skill.json", { auth: false })).files;
  const files = {};
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.name.startsWith(".")) continue;
      const path = join(dir, entry.name);
      if (entry.isDirectory()) walk(path);
      else files[relative(local, path)] = readFileSync(path, "utf8");
    }
  };
  walk(local);
  return files;
}

/** A git address fit to print: an HTTPS address loses any user name and password in it. */
function withoutCredentials(address) {
  try {
    const url = new URL(address);
    url.username = url.password = "";
    return url.href;
  } catch {
    return address;
  }
}

// --- Import helpers ----------------------------------------------------------------------------

/** One commit holding the folder's files (its .gitignore applies), in a repository of its own. */
function snapshot(folder, work, name) {
  const gitDir = join(work, "repo.git");
  const env = { ...process.env, GIT_DIR: gitDir, GIT_WORK_TREE: folder };
  git(["init", "--quiet", "-b", "main"], { env, cwd: folder });
  git(["add", "-A"], { env, cwd: folder });
  const author = ["-c", "user.name=Usual Base import", "-c", "user.email=import@usual.invalid"];
  const commit = gitTry([...author, "commit", "--quiet", "--no-verify", "-m", `Import ${name}`], { env, cwd: folder });
  if (!commit.ok) fail(/nothing to commit/.test(commit.out) ? "The folder has no files to import." : commit.out.trim());
  return { gitDir, head: git(["rev-parse", "HEAD"], { env, cwd: folder }) };
}

/** The folder's own history: the repository's, or only the folder's commits if it's a subfolder. */
function historyHead(folder, work) {
  const top = gitTry(["-C", folder, "rev-parse", "--show-toplevel"]);
  if (!top.ok) fail("--history needs a folder inside a git repository.");
  // git reports the real path (macOS's /var is /private/var), so compare real paths.
  const prefix = relative(top.out.trim(), realpathSync(folder));
  // A scratch clone, so splitting the folder's history out leaves the original repository untouched.
  const clone = join(work, "repo");
  git(["clone", "--quiet", "--no-checkout", top.out.trim(), clone]);
  const gitDir = join(clone, ".git");
  if (!prefix) return { gitDir, head: git(["--git-dir", gitDir, "rev-parse", "HEAD"]) };
  const split = gitTry(["-C", clone, "subtree", "split", "--prefix", prefix, "HEAD"]);
  if (!split.ok) fail(`Couldn't take the folder's history out (git subtree): ${split.out.trim()}`);
  return { gitDir, head: split.stdout.trim().split("\n").pop() };
}

function checkSizes({ gitDir, head }) {
  const listing = git(["--git-dir", gitDir, "ls-tree", "-r", "-l", head], { maxBuffer: 1 << 28 });
  const tooBig = listing.split("\n").filter(Boolean)
    .map((line) => line.split(/\s+/))
    .filter((parts) => Number(parts[3]) > MAX_FILE_BYTES)
    .map((parts) => parts.slice(4).join(" "));
  if (tooBig.length) fail(`Files over 32 MiB can't be stored; remove or ignore them first:\n  ${tooBig.join("\n  ")}`);
}

/** Pushes history oldest first, in batches small enough for Artifacts' per-push object limit. */
function pushInBatches({ gitDir, head }, url) {
  const commits = git(["--git-dir", gitDir, "rev-list", "--reverse", "--first-parent", head], { maxBuffer: 1 << 28 })
    .split("\n").filter(Boolean);
  let index = 0;
  let step = Math.max(1, commits.length);
  while (index < commits.length) {
    const target = commits[Math.min(index + step, commits.length) - 1];
    const result = gitTry(["--git-dir", gitDir, "push", "--quiet", url, `${target}:refs/heads/main`]);
    if (result.ok) {
      index = Math.min(index + step, commits.length);
      continue;
    }
    if (step > 1 && /memory budget|failed to report status|too many objects/i.test(result.out)) {
      step = Math.ceil(step / 2);
      continue;
    }
    if (step === 1 && /memory budget/i.test(result.out)) {
      fail(`One commit holds more than ${MAX_OBJECTS.toLocaleString()} objects, too many for one push.`);
    }
    if (/non-fast-forward|fetch first|rejected/i.test(result.out)) {
      fail("The repository's main branch already has other history. Import into an empty repository.");
    }
    fail(`Push failed: ${result.out.trim()}`);
  }
}

// --- Main --------------------------------------------------------------------------------------

const help = `Usual Base CLI ${VERSION}

With any git repository (GitHub, GitLab, Forgejo, a bare repository…):
  usual-base sync [PATH]                         pull, then push your commits
  usual-base import <folder> --to GIT_URL [--history]
                                                 push an existing knowledge base into an empty repository
  usual-base skill [--to DIR]                    install the usual-base agent skill

With a Usual Base server (${server}):
  usual-base connect [--name NAME] [--dir DIR]   connect this machine; you approve it in the browser
  usual-base bases                               list the Bases this token can read
  usual-base clone <base>… | --all [--dir DIR]   clone Bases (default folder: ~/Usual Base)
  usual-base import <folder> --name NAME [--history]
                                                 create a Base from an existing knowledge base
  usual-base path <base>                         print where a Base is cloned
  usual-base whoami | logout

--history keeps the folder's git history, even for a subfolder of a bigger repository.
USUAL_BASE_TOKEN, USUAL_BASE_SERVER and USUAL_BASE_DIR override the saved settings.`;

const [command, ...rest] = process.argv.slice(2);
if (!command || command === "help" || command === "--help" || command === "-h") console.log(help);
else if (command === "--version" || command === "version") console.log(VERSION);
else if (!commands[command]) {
  console.error(`Unknown command: ${command}\n\n${help}`);
  process.exit(2);
} else {
  commands[command](parse(rest)).catch((error) => {
    console.error(error instanceof Failure ? error.message : error.stack || String(error));
    process.exit(1);
  });
}
