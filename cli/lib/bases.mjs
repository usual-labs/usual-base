// Bases on this machine: where they're cloned, syncing them, and importing a folder.

import { existsSync, mkdirSync, realpathSync } from "node:fs";
import { join, relative } from "node:path";
import { config, fail, git, gitTry, MAX_FILE_BYTES, MAX_OBJECTS } from "./core.mjs";

export function folderName(name) {
  return name.replace(/[\/\\:*?"<>|]/g, "-").replace(/^\.+/, "").trim() || "Base";
}

/** The folder `init` made into this Base, if it's still that Base. */
export function initFolder(base) {
  const folder = config.folders?.[base.id];
  return folder && gitTry(["-C", folder, "config", "--get", "usualbase.base"]).stdout.trim() === base.id ? folder : null;
}

/** Where this Base is on this machine: the folder `init` made it, or its clone in the Bases folder `root`. */
export function localFolder(base, root) {
  const kept = initFolder(base);
  if (kept) return kept;
  const clone = join(root, folderName(base.name));
  return existsSync(join(clone, ".git")) && gitTry(["-C", clone, "config", "--get", "usualbase.base"]).stdout.trim() === base.id
    ? clone
    : null;
}

export function cloneBase(base, root) {
  const here = localFolder(base, root);
  if (here) {
    console.log(`${base.name}: already at ${here}`);
    return here;
  }
  const target = join(root, folderName(base.name));
  if (existsSync(join(target, ".git"))) fail(`${target} already holds another repository. Use --dir to clone somewhere else.`);
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
