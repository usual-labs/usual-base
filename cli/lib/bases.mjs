// Bases on this machine: where they're cloned, making a folder a Base (init), and importing a folder.

import { existsSync, mkdirSync, mkdtempSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, relative } from "node:path";
import { createInterface } from "node:readline";
import { ask, call, config, fail, git, gitTry, MAX_FILE_BYTES, MAX_OBJECTS } from "./core.mjs";

export function folderName(name) {
  return name.replace(/[\/\\:*?"<>|]/g, "-").replace(/^\.+/, "").trim() || "Base";
}

/** The folder `init` made into this Base, if it's still that Base. */
export function initFolder(base) {
  const folder = config.folders?.[base.id];
  return folder && gitTry(["-C", folder, "config", "--get", "usualbase.base"]).stdout.trim() === base.id ? folder : null;
}

export function cloneBase(base, root) {
  const kept = initFolder(base);
  if (kept) {
    console.log(`${base.name}: already at ${kept}`);
    return kept;
  }
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

/** Pulls with rebase, then pushes this clone's commits, retrying when others pushed first. Never force-pushes. */
export function syncRepo(dir) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const pull = gitTry(["-C", dir, "pull", "--rebase", "--autostash", "--quiet"]);
    if (!pull.ok && !/couldn't find remote ref|no such ref/i.test(pull.out)) fail(`Pull failed: ${pull.out.trim()}`);
    const ahead = gitTry(["-C", dir, "rev-list", "--count", "@{upstream}..HEAD"]);
    if (ahead.ok && Number(ahead.out.trim()) === 0) return "up to date";
    const push = gitTry(["-C", dir, "push", "--quiet", "-u", "origin", "HEAD"]);
    if (push.ok) return "pushed";
    if (!/rejected|fetch first|stale/i.test(push.out)) fail(`Push failed: ${push.out.trim()}`);
  }
  fail("Others kept pushing; run `usual-base sync` again.");
}

/** A git address fit to print: an HTTPS address loses any user name and password in it. */
export function withoutCredentials(address) {
  try {
    const url = new URL(address);
    url.username = url.password = "";
    return url.href;
  } catch {
    return address;
  }
}

// --- Init helpers ------------------------------------------------------------------------------

/** The files a first commit of the folder would hold: its .gitignore and git's own ignore settings apply. */
export function folderFiles(folder) {
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

/**
 * The Base for `init`: the one --base names, a new one called --name, or the person's choice when there's a
 * terminal to ask in. A folder with files is offered only empty Bases; the server's answer still decides.
 */
export async function chooseBase(flags, folder, hasFiles, canCreate) {
  const { bases } = await call("/api/bases");
  if (typeof flags.base === "string") {
    return bases.find((b) => b.id === flags.base || b.name === flags.base) || fail(`No Base called ${flags.base}; see \`usual-base bases\`.`);
  }
  const create = async (name) => {
    const { base } = await call("/api/bases", { method: "POST", body: { name } });
    console.log(`Created Base "${base.name}" (${base.id}).`);
    return base;
  };
  if (typeof flags.name === "string") return create(flags.name);
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    fail("Choose the Base with --base <id or name>, or create one with --name <name>.");
  }
  const offered = hasFiles ? bases.filter((b) => !b.lastPushAt) : bases;
  if (!offered.length && !canCreate) {
    fail(hasFiles ? "This token has no empty Base to put the folder in, and can't create one." : "This token can't use any Bases yet.");
  }
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  rl.on("SIGINT", () => rl.close());
  try {
    if (offered.length) {
      console.log(`Which Base should ${folder} become?${hasFiles ? " Bases with notes aren't listed, since the folder has files." : ""}`);
      offered.forEach((base, i) => console.log(`  ${i + 1}. ${base.name} (${base.id})`));
      if (canCreate) console.log("  n. A new Base");
      const choices = `1${offered.length > 1 ? `–${offered.length}` : ""}${canCreate ? " or n" : ""}`;
      for (;;) {
        const answer = (await ask(rl, `Choose ${choices}: `)).trim().toLowerCase();
        const number = Number(answer);
        if (Number.isInteger(number) && number >= 1 && number <= offered.length) return offered[number - 1];
        if (canCreate && answer === "n") break;
        console.log(`Type ${choices}.`);
      }
    } else {
      console.log(hasFiles ? "There's no empty Base for the folder's files, so they go into a new one." : "There's no Base yet, so this creates one.");
    }
    const suggested = basename(folder);
    return create((await ask(rl, `Name for the new Base [${suggested}]: `)).trim() || suggested);
  } finally {
    rl.close();
  }
}

// --- Import helpers ----------------------------------------------------------------------------

/** One commit holding the folder's files (its .gitignore applies), in a repository of its own. */
export function snapshot(folder, work, name) {
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
export function historyHead(folder, work) {
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

export function checkSizes({ gitDir, head }) {
  const listing = git(["--git-dir", gitDir, "ls-tree", "-r", "-l", head], { maxBuffer: 1 << 28 });
  const tooBig = listing.split("\n").filter(Boolean)
    .map((line) => line.split(/\s+/))
    .filter((parts) => Number(parts[3]) > MAX_FILE_BYTES)
    .map((parts) => parts.slice(4).join(" "));
  if (tooBig.length) fail(`Files over 32 MiB can't be stored; remove or ignore them first:\n  ${tooBig.join("\n  ")}`);
}

/** Pushes history oldest first, in batches small enough for Artifacts' per-push object limit. */
export function pushInBatches({ gitDir, head }, url) {
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
