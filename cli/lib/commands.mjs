// The commands, by name.

import { existsSync, lstatSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir, hostname, tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { basesDir, call, config, DEFAULT_SERVER, fail, git, gitTry, MAX_FILE_BYTES, server, setUpCredentialHelper, sharedBy, shown, token, VERSION, writeConfig } from "./core.mjs";
import { checkSizes, chooseBase, cloneBase, folderFiles, folderName, historyHead, initFolder, pushInBatches, snapshot, syncRepo, withoutCredentials } from "./bases.mjs";
import { roomActions } from "./rooms.mjs";
import { readerName, roomsBase } from "./room-store.mjs";
import { doctor, linkedTo, skillFiles, update, writeSkill } from "./upkeep.mjs";

// --- Commands ----------------------------------------------------------------------------------

const access = (token) => `${token.scope === "write" ? "read and write" : "read only"}, ${token.allBases ? "all Bases" : `${token.baseIds.length} Bases`}`;

/** The token this machine saved for this server, if any (not USUAL_BASE_TOKEN: that one isn't the machine's). */
const savedToken = () => (config.token && (config.server || DEFAULT_SERVER) === server ? config.token : null);
const withToken = (secret, path, method = "GET") => fetch(server + path, {
  method,
  headers: { authorization: `Bearer ${secret}`, "user-agent": `usual-cli/${VERSION}` },
  signal: AbortSignal.timeout(30_000),
});

/** What this machine's saved connection may do, or null when it has none, or none that still works. */
async function savedConnection() {
  if (!savedToken()) return null;
  const response = await withToken(savedToken(), "/api/me");
  if (response.status === 401) return null; // revoked
  if (!response.ok) fail(`${server}/api/me answered HTTP ${response.status}; try again later.`);
  return response.json();
}

export const commands = {
  /**
   * Connects this machine. Its agents share one connection: once it has one that works, another agent's `connect`
   * keeps it and only adds that agent's name, unless --again asks for a new one (other Bases or access).
   */
  async connect({ flags }) {
    const name = typeof flags.name === "string" && flags.name.trim() ? flags.name.trim() : `Agent on ${hostname()}`;
    const current = flags.again ? null : await savedConnection();
    let dir = basesDir(flags);
    if (current) {
      dir = config.dir || dir;
      Object.assign(config, { agentNames: [...new Set([...sharedBy(), name])] });
      writeConfig(config);
      console.log(`This machine is already connected as "${config.name}" (${access(current.token)}). Its agents share ` +
        `that connection${name === config.name ? "" : `, so "${name}" uses it too`}; \`usual-base connect --again\` replaces it.`);
    } else {
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
      // --again: the old token was this machine's alone, so it goes once the new one is saved.
      const old = flags.again && savedToken() && { secret: savedToken(), name: config.name };
      Object.assign(config, { server, token: result.token, tokenId: result.token_id, name, dir, agentNames: [name] });
      writeConfig(config);
      setUpCredentialHelper();
      console.log(`\nConnected as "${name}".`);
      if (old) {
        const status = await withToken(old.secret, "/api/token/revoke", "POST").then((r) => r.status, () => 0);
        if (status === 200) console.log(`Revoked the connection it replaces, "${old.name}".`);
        else if (status !== 401) console.log(`Couldn't revoke the connection it replaces, "${old.name}"; revoke it in ${server}/agents.`);
      }
    }
    if (!flags["no-clone"]) await commands.clone({ args: [], flags: { ...flags, all: true, dir } });
    if (!flags["no-skill"]) await commands.skill({ flags });
    // An agent sharing the connection names itself in rooms; the first one is the connection's name.
    const asLine = current
      ? `\n- In its rooms I am "${name}": I add --as "${name}" to \`usual-base room\` commands and to \`usual-base sync -m\`.`
      : "";
    console.log(`
Add these lines to your global instructions (for example ~/.claude/CLAUDE.md or ~/.codex/AGENTS.md):

- Usual Base: ${dir} holds my Bases, git clones of ${server}. Run \`usual-base sync\` in a Base before reading and after committing.
- Use the usual-base skill to look things up there before asking, and to save what should outlast this session.${asLine}`);
  },

  async whoami() {
    const me = await call("/api/me");
    console.log(`${me.user.name} <${me.user.email}> via "${me.token.name}" (${access(me.token)}) on ${server}`);
    if (sharedBy().length > 1) console.log(`Agents sharing this connection: ${sharedBy().map((n) => `"${n}"`).join(", ")}.`);
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
    console.log(initFolder(base) || join(basesDir(flags), folderName(base.name)));
  },

  /** Makes a folder a Base where it is: its files go into an empty Base, or an empty folder gets the Base's. */
  async init({ args, flags }) {
    const folder = resolve(args[0] || ".");
    if (!statSync(folder, { throwIfNoEntry: false })?.isDirectory()) fail(`${folder} isn't a folder.`);
    if (flags.base !== undefined && flags.name !== undefined) fail("Use --base for an existing Base or --name for a new one, not both.");
    const top = gitTry(["-C", folder, "rev-parse", "--show-toplevel"]);
    if (top.ok) {
      const own = top.stdout.trim() === realpathSync(folder);
      const id = own && gitTry(["-C", folder, "config", "--get", "usualbase.base"]).stdout.trim();
      if (id) return console.log(`${folder} is already the Base ${id}. Commit your changes and run \`usual-base sync\` in it.`);
      fail(own
        ? `${folder} is already a git repository. To copy it into a Base with its history, run \`usual-base import "${folder}" --history\`.`
        : `${folder} is inside the git repository ${top.stdout.trim()}, and a Base can't live inside another repository. ` +
          `To copy it into a Base, run \`usual-base import "${folder}" --history\`.`);
    }

    const me = await call("/api/me");
    if (me.token.scope !== "write") fail("This token can only read. Run `usual-base connect --again` and allow writing.");
    const files = folderFiles(folder);
    const tooBig = files.filter((file) => lstatSync(join(folder, file)).size > MAX_FILE_BYTES);
    if (tooBig.length) fail(`Files over 32 MiB can't be stored; remove or ignore them first:\n  ${tooBig.join("\n  ")}`);
    const base = await chooseBase(flags, folder, files.length > 0, me.token.allBases);
    setUpCredentialHelper();
    const remote = gitTry(["ls-remote", base.git, "refs/heads/main"]);
    if (!remote.ok) fail(`Couldn't reach ${base.name}: ${remote.out.trim()}`);
    const baseHasNotes = remote.stdout.trim() !== "";
    if (baseHasNotes && files.length) {
      fail(`"${base.name}" already has notes and ${folder} has files too, so neither can become the other. ` +
        "Choose an empty Base or a new one, or start from an empty folder.");
    }

    const dotGit = join(folder, ".git");
    try {
      git(["init", "--quiet", "-b", "main", folder]);
      writeFileSync(join(dotGit, "info", "exclude"), ".DS_Store\n", { flag: "a" }); // as the app's sync does
      git(["-C", folder, "remote", "add", "origin", base.git]);
      git(["-C", folder, "config", "usualbase.base", base.id]);
      if (baseHasNotes) {
        git(["-C", folder, "fetch", "--quiet", "origin"]);
        // checkout refuses to overwrite an ignored file in the way, where reset --hard wouldn't.
        git(["-C", folder, "checkout", "--quiet", "-b", "main", "--track", "origin/main"]);
      } else if (files.length) {
        git(["-C", folder, "add", "-A"]);
        const identity = gitTry(["-C", folder, "var", "GIT_AUTHOR_IDENT"]).ok ? [] : ["-c", "user.name=Usual Base", "-c", "user.email=init@usual.invalid"];
        git([...identity, "-C", folder, "commit", "--quiet", "--no-verify", "-m", `Start ${base.name}`]);
        pushInBatches({ gitDir: dotGit, head: git(["-C", folder, "rev-parse", "HEAD"]) }, base.git);
        // Only conveniences from here: `usual-base sync` sets the upstream itself if this fails.
        if (gitTry(["-C", folder, "fetch", "--quiet", "origin"]).ok) gitTry(["-C", folder, "branch", "--quiet", "--set-upstream-to=origin/main", "main"]);
      }
    } catch (error) {
      rmSync(dotGit, { recursive: true, force: true }); // the folder is as it was
      throw error;
    }
    config.folders = { ...config.folders, [base.id]: folder };
    writeConfig(config);
    const what = baseHasNotes ? "with its notes" : files.length ? `with your ${files.length} files pushed` : "empty so far";
    console.log(`${folder} is now the Base "${base.name}" (${base.id}), ${what}.`);
    console.log(`Commit your changes and run \`usual-base sync\` in it. See it at ${server}/bases/${base.id}`);
  },

  async sync({ args, flags }) {
    const dir = resolve(args[0] || ".");
    const top = gitTry(["-C", dir, "rev-parse", "--show-toplevel"]);
    if (!top.ok) fail(`${dir} isn't a Base clone.`);
    const status = git(["-C", dir, "status", "--porcelain"]);
    if (status && typeof flags.message === "string") {
      // `-m` commits every change under the writer's name, so an agent needs only this command to save notes.
      const writer = readerName(top.stdout.trim(), flags);
      const email = gitTry(["-C", dir, "config", "user.email"]).stdout.trim() || "agent@agents.invalid";
      git(["-C", dir, "add", "-A"]);
      git(["-C", dir, "-c", `user.name=${writer}`, "-c", `user.email=${email}`, "commit", "--quiet", "--no-verify", "-m", flags.message]);
    } else if (status) console.log("Uncommitted changes stay local; commit them (or pass -m), then sync again to push them.");
    console.log(syncRepo(dir) === "pushed" ? "Pushed." : "Up to date.");
  },

  /** Sets an agent platform up for a Base: `setup claude-code <project folder>` or `setup hermes <profile>…`. */
  async setup({ args, flags }) {
    const [platform, ...rest] = args;
    if (platform === "hermes") return (await import("./hermes.mjs")).setupHermes({ args: rest, flags });
    if (platform !== "claude-code") fail("usual-base setup claude-code <project folder> | hermes <profile>… [--name NAME] [--base BASE] [--wake] [--remove]");
    return (await import("./claude-code.mjs")).setupClaudeCode({ args: rest, flags });
  },

  /** What an agent platform's hooks run. Today: `hook claude-code`, reading the hook's JSON on stdin. */
  async hook({ args }) {
    if (args[0] === "claude-code") return (await import("./claude-code.mjs")).claudeCodeHook(args);
  },

  /** Wakes agents when someone posts in their rooms; `relay install | uninstall | status`. */
  async relay({ args, flags }) {
    return (await import("./relay.mjs")).relay({ args, flags });
  },

  /** Rooms: `room list | create | read | say | wait | join | leave | news`, in the Base `roomsBase` finds. */
  async room({ args, flags }) {
    const [action, ...rest] = args;
    const run = roomActions[action] ||
      fail("usual-base room list | create <name> | read <room> | say <room> <message> | wait <room>");
    return run(roomsBase(flags), rest, flags);
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
      const link = linkedTo(target);
      if (link) console.log(`Left ${shown(target)} alone: it links to ${shown(link)}, so update that copy.`);
      else {
        writeSkill(target, files);
        console.log(`Installed the usual-base skill in ${target}`);
      }
    }
  },

  async logout() {
    writeConfig({ ...config, token: undefined, tokenId: undefined, agentNames: undefined });
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
  update,
  doctor,
};
