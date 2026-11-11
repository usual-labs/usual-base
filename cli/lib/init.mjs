// `usual-base init`: a folder becomes a Base where it is. In a terminal without a folder, it sets up a Base for the
// project in the current folder: which Base, where its folder goes and whether Claude Code uses it, all asked first,
// then done once the person agrees.
//
// The folder may sit inside a project's git repository. It becomes a repository of its own, and the project's
// .git/info/exclude ignores it, so the project's commits never take it in. A folder with files the project tracks
// can't be one: both repositories would claim them.

import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir, hostname, tmpdir } from "node:os";
import { basename, dirname, join, relative, resolve, sep } from "node:path";
import { createInterface } from "node:readline";
import { ask, basesDir, call, config, confirm, fail, Failure, git, gitTry, MAX_FILE_BYTES, server, setUpCredentialHelper, shown, writeConfig } from "./core.mjs";
import { folderName, localFolder, pushInBatches } from "./bases.mjs";
import { access, approveMachine, connection } from "./connection.mjs";
import { claudeAgents, setupClaudeCode } from "./claude-code.mjs";

export async function init({ args, flags }) {
  if (flags.base !== undefined && flags.name !== undefined) fail("Use --base for an existing Base or --name for a new one, not both.");
  const terminal = Boolean(process.stdin.isTTY && process.stdout.isTTY);
  if (!args.length && flags.base === undefined && flags.name === undefined && terminal) return initProject();
  return initFolder(resolve(args[0] || "."), flags, terminal);
}

/** `init <folder> [--base BASE | --name NAME]`: the folder becomes the Base, asking which only in a terminal. */
async function initFolder(folder, flags, terminal) {
  const found = inspectFolder(folder);
  if (found.baseId) return console.log(`${folder} is already the Base ${found.baseId}. Commit your changes and run \`usual-base sync\` in it.`);
  if (found.problem) fail(found.problem);
  const me = await call("/api/me");
  const { bases } = await call("/api/bases");
  let choice;
  if (typeof flags.base === "string") {
    choice = bases.find((b) => b.id === flags.base || b.name === flags.base) || fail(`No Base called ${flags.base}; see \`usual-base bases\`.`);
  } else if (typeof flags.name === "string") choice = { create: flags.name };
  else if (!terminal) fail("Choose the Base with --base <id or name>, or create one with --name <name>.");
  else {
    const hasFiles = found.files.length > 0;
    choice = await inTerminal((rl) => chooseBase(rl, {
      question: `Which Base should ${folder} become?${hasFiles ? " Bases with notes aren't listed, since the folder has files." : ""}`,
      bases: hasFiles ? bases.filter((b) => !b.lastPushAt) : bases,
      canCreate: canCreate(me),
      suggested: basename(folder),
      none: hasFiles ? "There's no empty Base for the folder's files, so they go into a new one." : "There's no Base yet, so this creates one.",
      nothing: hasFiles ? "This connection has no empty Base to put the folder in, and can't create one." : "This connection can't use any Bases yet.",
    }));
  }
  const notes = !choice.create && hasNotes(choice);
  const problem = mismatch(folder, found, choice, notes, me);
  if (problem) fail(problem);
  place(folder, await created(choice), found, notes);
}

// --- A Base for this project -------------------------------------------------------------------

/** `init` in a terminal, without a folder: a Base for the project in the current folder. */
async function initProject() {
  const project = realpathSync(process.cwd());
  console.log(`A Base for ${shown(project)}. Nothing changes until you agree at the end.\n`);
  const here = inspectFolder(project);
  let me = null;
  let connectedNow = false;
  if (!here.baseId) {
    me = await connection();
    if (me) console.log(`Connected to ${server} as "${me.token.name}" (${access(me.token)}).`);
    else {
      console.log(`This computer isn't connected to ${server} yet. You approve it in the browser and choose which Bases it may use.`);
      if (!(await inTerminal((rl) => confirm(rl, "Connect it now? [Y/n] ", true)))) return console.log("Nothing changed.");
      await approveMachine({ name: `Agent on ${hostname()}`, dir: basesDir({}) });
      connectedNow = true;
      me = (await connection()) || fail("The new connection doesn't work; run `usual-base doctor`.");
    }
  }
  let plan;
  try {
    plan = await inTerminal((rl) => planProject(rl, project, here, me));
  } catch (error) {
    if (connectedNow && error instanceof Failure) throw new Failure(error.message.replace("nothing changed", "this computer stays connected, and nothing else changed"));
    throw error;
  }
  if (!plan) return;
  const { base, folder, found, notes, claude } = plan;
  console.log("");
  if (base && !found.baseId) place(folder, await created(base), found, notes);
  if (claude) {
    if (base && !found.baseId) console.log("");
    await setupClaudeCode({ args: [project], flags: { name: claude.name, base: folder, wake: claude.wake } });
  } else if (folder !== project) {
    console.log(`\nTo have Claude Code in this project use it later: usual-base setup claude-code "${project}" --base "${folder}"`);
  }
}

/** The questions, in order; returns what to do, or null when the person says no at the end. */
async function planProject(rl, project, here, me) {
  let base = null;
  let folder = project;
  let found = here;
  let notes = false;
  if (here.baseId) console.log(`${shown(project)} is already a Base (${here.baseId}).`);
  else {
    const { bases } = await call("/api/bases");
    console.log("");
    base = await chooseBase(rl, {
      question: `Which Base should ${shown(project)} use?`,
      bases,
      canCreate: canCreate(me),
      suggested: basename(project),
      where: (b) => localFolder(b, basesDir({})),
      none: "There's no Base yet, so this creates one.",
      nothing: "This connection can't use any Bases yet, and can't create one.",
    });
    notes = !base.create && hasNotes(base);
    ({ folder, found } = await chooseFolder(rl, project, base, notes, me));
  }

  const agent = claudeAgents().find((a) => a.path === project);
  let claude = null;
  console.log("");
  if (await confirm(rl, `Set up Claude Code in ${shown(project)} to use this Base? [Y/n] `, true)) {
    const fallback = agent?.name || `Claude Code in ${basename(project)}`;
    const name = (await ask(rl, `Its name in rooms [${fallback}]: `)).trim() || fallback;
    const wake = await confirm(rl, `Start Claude Code when someone posts in its rooms and no session is open? ${agent?.wake ? "[Y/n]" : "[y/N]"} `, Boolean(agent?.wake));
    claude = { name, wake };
  }

  const steps = [base && !found.baseId && baseStep(base, folder, found, notes)].filter(Boolean);
  if (base && found.baseId) steps.push(`use the Base "${base.name}" at ${shown(folder)}, where it is now`);
  if (claude) steps.push(`set up Claude Code in ${shown(project)} as "${claude.name}", ${claude.wake ? "woken when someone posts in its rooms" : "without waking"}`);
  if (!steps.length) {
    console.log("Nothing to do.");
    return null;
  }
  console.log(`\nReady to:\n${steps.map((step) => `- ${step}`).join("\n")}`);
  if (!(await confirm(rl, "Go ahead? [Y/n] ", true))) {
    console.log("Nothing changed.");
    return null;
  }
  return { base, folder, found, notes, claude };
}

function baseStep(base, folder, found, notes) {
  const what = base.create ? `create the Base "${base.create}" in ${shown(folder)}` : `put the Base "${base.name}" in ${shown(folder)}`;
  const contents = notes ? ", with its notes" : found.files.length ? `, with the folder's ${count(found.files)}` : found.exists ? "" : ", a new folder";
  const ignored = found.enclosing ? `; ${shown(found.enclosing.root)}'s git will ignore that folder` : "";
  return what + contents + ignored;
}

/** Where the Base's folder goes: offered places that work, or a folder the person types. */
async function chooseFolder(rl, project, base, notes, me) {
  const fits = (folder) => {
    const found = inspectFolder(folder);
    if (found.baseId) return found.baseId === base.id ? { folder, found } : { problem: `${shown(folder)} is already another Base (${found.baseId}).` };
    const problem = found.problem || mismatch(folder, found, base, notes, me);
    return problem ? { problem } : { folder, found };
  };
  const bases = basesDir({});
  const inProject = (folder) => folder === project || inside(folder, project);
  const label = ({ folder, found }) => [
    folder === project ? "this folder itself" : inside(folder, project) ? "inside this project" : inside(folder, bases) ? "with your other Bases" : null,
    found.baseId ? "where it is now" : !found.exists ? "new" : found.files.length && !notes ? `${count(found.files)} to add` : null,
  ].filter(Boolean).join(", ");
  // Where the Base is already comes first, inside this project before elsewhere; then new places, inside first.
  const rank = ({ folder, found }) => (found.baseId ? 0 : 2) + (inProject(folder) ? 0 : 1);
  const places = [join(project, "base"), project, base.id && localFolder(base, bases), join(bases, folderName(base.create ?? base.name))]
    .filter((folder, i, all) => folder && all.indexOf(folder) === i)
    .map(fits)
    .filter((offer) => !offer.problem)
    .sort((a, b) => rank(a) - rank(b));

  console.log("\nWhere should its folder be? Inside the project, Claude Code reads and edits the Base like the project's");
  console.log("own files, and the project's git ignores it.");
  places.forEach((offer, i) => console.log(`  ${i + 1}. ${shown(offer.folder)} (${label(offer)})`));
  console.log(`  ${places.length ? "Or type" : "Type"} a folder, relative to this project.`);
  for (;;) {
    const answer = (await ask(rl, places.length ? "Choose [1]: " : "Folder: ")).trim();
    if (!answer && !places.length) continue;
    const number = answer ? Number(answer) : 1;
    if (Number.isInteger(number) && number >= 1 && number <= places.length) return places[number - 1];
    if (/^\d+$/.test(answer)) {
      console.log(`Type ${places.length > 1 ? `1–${places.length}, or ` : places.length ? "1, or " : ""}a folder (./${answer} for one with that name).`);
      continue;
    }
    const offer = fits(resolve(project, answer.replace(/^~(?=$|\/)/, homedir())));
    if (!offer.problem) return offer;
    console.log(offer.problem);
  }
}

// --- Shared steps ------------------------------------------------------------------------------

async function inTerminal(use) {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  rl.on("SIGINT", () => rl.close());
  try {
    return await use(rl);
  } finally {
    rl.close();
  }
}

const count = (files) => `${files.length} file${files.length === 1 ? "" : "s"}`;
const canCreate = (me) => me.token.allBases && me.token.scope === "write";
const inside = (dir, folder) => dir.startsWith(folder.endsWith(sep) ? folder : folder + sep);

/**
 * An existing Base, or { create: name } for a new one, made only once everything else checks out. A `where`
 * function shows the Bases this machine has already.
 */
async function chooseBase(rl, { question, bases, canCreate, suggested, where = () => null, none, nothing }) {
  if (!bases.length && !canCreate) fail(nothing);
  if (bases.length) {
    console.log(question);
    bases.forEach((base, i) => {
      const at = where(base);
      console.log(`  ${i + 1}. ${base.name} (${base.id})${at ? `, here at ${shown(at)}` : ""}`);
    });
    if (canCreate) console.log("  n. A new Base");
    const choices = `1${bases.length > 1 ? `–${bases.length}` : ""}${canCreate ? " or n" : ""}`;
    for (;;) {
      const answer = (await ask(rl, `Choose ${choices}: `)).trim().toLowerCase();
      const number = Number(answer);
      if (answer && Number.isInteger(number) && number >= 1 && number <= bases.length) return bases[number - 1];
      if (canCreate && answer === "n") break;
      console.log(`Type ${choices}.`);
    }
  } else console.log(none);
  return { create: (await ask(rl, `Name for the new Base [${suggested}]: `)).trim() || suggested };
}

async function created(choice) {
  if (!choice.create) return choice;
  const { base } = await call("/api/bases", { method: "POST", body: { name: choice.create } });
  console.log(`Created Base "${base.name}" (${base.id}).`);
  return base;
}

/** Whether a Base already has notes, from the server's git. */
function hasNotes(base) {
  setUpCredentialHelper();
  const remote = gitTry(["ls-remote", base.git, "refs/heads/main"]);
  if (!remote.ok) fail(`Couldn't reach ${base.name}: ${remote.out.trim()}`);
  return remote.stdout.trim() !== "";
}

/** Why this folder can't become this Base, if it can't. */
function mismatch(folder, found, choice, notes, me) {
  if (notes && found.files.length) {
    return `"${choice.name}" already has notes and ${shown(folder)} has files too, so neither can become the other. ` +
      "Choose an empty Base or a new one, or an empty folder.";
  }
  if ((choice.create || found.files.length) && me.token.scope !== "write") {
    return "This computer's connection can only read, so it can't create a Base or add files to one. " +
      "Run `usual-base connect --again` and allow writing.";
  }
  return null;
}

const configured = (repo, key) => gitTry(["-C", repo, "config", "--get", key]).stdout.trim();

/**
 * What a folder is to git, and whether it can become a Base: { baseId } when it's a Base already, { problem }, or
 * { exists, files, enclosing }, where `enclosing` is the project repository it would sit in: { root, path }.
 */
export function inspectFolder(folder) {
  let existing = folder;
  while (!existsSync(existing)) existing = dirname(existing);
  if (!statSync(existing).isDirectory()) return { problem: `${shown(existing)} isn't a folder.` };
  const exists = existing === folder;
  const real = join(realpathSync(existing), relative(existing, folder));
  const top = gitTry(["-C", existing, "rev-parse", "--show-toplevel"]);
  let enclosing = null;
  if (top.ok) {
    const root = top.stdout.trim();
    if (root === real) {
      const id = configured(root, "usualbase.base");
      return id ? { baseId: id } : {
        problem: `${shown(folder)} is already a git repository. To copy it into a Base with its history, run ` +
          `\`usual-base import "${folder}" --history\`.`,
      };
    }
    if (configured(root, "usualbase.base") || configured(root, "usualbase.sync") === "true") {
      return { problem: `${shown(folder)} is inside the Base at ${shown(root)}, and a Base can't hold another.` };
    }
    const path = relative(root, real);
    if (gitTry(["--literal-pathspecs", "-C", root, "ls-files", "--", path]).stdout.trim()) {
      return {
        problem: `${shown(folder)} holds files that the git repository ${shown(root)} tracks, so it can't be a Base of its ` +
          `own. Choose a folder that repository doesn't track, or stop tracking it there first (\`git -C "${root}" rm -r ` +
          `--cached "${path}"\`, ignore it and commit).`,
      };
    }
    enclosing = { root, path };
  }
  const files = exists ? folderFiles(folder) : [];
  // git lists a repository inside the folder as its folder, which a Base would keep as a broken link.
  const repositories = files.filter((file) => file.endsWith("/"));
  if (repositories.length) {
    return { problem: `${shown(folder)} holds git repositories (${repositories.map((r) => r.slice(0, -1)).join(", ")}), which a Base can't hold. Choose a folder without them.` };
  }
  const tooBig = files.filter((file) => lstatSync(join(folder, file)).size > MAX_FILE_BYTES);
  if (tooBig.length) return { problem: `Files over 32 MiB can't be stored; remove or ignore them first:\n  ${tooBig.join("\n  ")}` };
  return { exists, files, enclosing };
}

/** The files a first commit of the folder would hold: its .gitignore and git's own ignore settings apply. */
function folderFiles(folder) {
  const probe = mkdtempSync(join(tmpdir(), "usual-init-"));
  try {
    git(["init", "--quiet", "--bare", probe]);
    const list = git(["--git-dir", probe, "--work-tree", folder, "ls-files", "-z", "--others", "--exclude-standard",
      "--exclude=.DS_Store"], { cwd: folder, maxBuffer: 1 << 28 });
    return list.split("\0").filter(Boolean);
  } finally {
    rmSync(probe, { recursive: true, force: true });
  }
}

/** Makes the folder the Base's clone: its files go into an empty Base, or an empty folder gets the Base's notes. */
function place(folder, base, found, notes) {
  mkdirSync(folder, { recursive: true });
  const dotGit = join(folder, ".git");
  try {
    git(["init", "--quiet", "-b", "main", folder]);
    writeFileSync(join(dotGit, "info", "exclude"), ".DS_Store\n", { flag: "a" }); // as the app's sync does
    git(["-C", folder, "remote", "add", "origin", base.git]);
    git(["-C", folder, "config", "usualbase.base", base.id]);
    // main follows origin/main from the start, so `usual-base sync` can pull and push even before the Base has notes.
    git(["-C", folder, "config", "branch.main.remote", "origin"]);
    git(["-C", folder, "config", "branch.main.merge", "refs/heads/main"]);
    if (notes) {
      git(["-C", folder, "fetch", "--quiet", "origin"]);
      // checkout refuses to overwrite an ignored file in the way, where reset --hard wouldn't.
      git(["-C", folder, "checkout", "--quiet", "-b", "main", "--track", "origin/main"]);
    } else if (found.files.length) {
      git(["-C", folder, "add", "-A"]);
      const identity = gitTry(["-C", folder, "var", "GIT_AUTHOR_IDENT"]).ok ? [] : ["-c", "user.name=Usual Base", "-c", "user.email=init@usual.invalid"];
      git([...identity, "-C", folder, "commit", "--quiet", "--no-verify", "-m", `Start ${base.name}`]);
      pushInBatches({ gitDir: dotGit, head: git(["-C", folder, "rev-parse", "HEAD"]) }, base.git);
      gitTry(["-C", folder, "fetch", "--quiet", "origin"]); // a convenience: `usual-base sync` fetches too
    }
  } catch (error) {
    // The folder is as it was: without the .git this made, or gone if this made it.
    rmSync(found.exists ? dotGit : folder, { recursive: true, force: true });
    throw error;
  }
  if (found.enclosing) ignoreInProject(found.enclosing);
  config.folders = { ...config.folders, [base.id]: folder };
  writeConfig(config);
  const what = notes ? "with its notes" : found.files.length ? `with your ${count(found.files)} pushed` : "empty so far";
  console.log(`${folder} is now the Base "${base.name}" (${base.id}), ${what}.`);
  if (found.enclosing) {
    console.log(`${shown(found.enclosing.root)}'s git ignores it (in its .git/info/exclude), so the project's commits leave it alone.`);
  }
  console.log(`Commit your changes and run \`usual-base sync\` in it. See it at ${server}/bases/${base.id}`);
}

/** Adds the Base's folder to the enclosing repository's own exclude file, unless something ignores it already. */
function ignoreInProject({ root, path }) {
  if (gitTry(["-C", root, "check-ignore", "-q", `${path}/`]).ok) return;
  const file = resolve(root, git(["-C", root, "rev-parse", "--git-path", "info/exclude"]));
  mkdirSync(dirname(file), { recursive: true });
  const before = existsSync(file) ? readFileSync(file, "utf8") : "";
  const pattern = `/${path.split(sep).join("/").replace(/[\\*?[\]!#]/g, "\\$&")}/`;
  writeFileSync(file, `${before && !before.endsWith("\n") ? "\n" : ""}${pattern}\n`, { flag: "a" });
}
