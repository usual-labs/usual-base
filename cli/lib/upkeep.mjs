// Keeping this machine current: the skill's copies, the CLI and its `ubase` link, `update`, `doctor`, and the
// daily check.

import { accessSync, constants, existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, realpathSync, renameSync, symlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, delimiter, dirname, join, relative } from "node:path";
import { createInterface } from "node:readline";
import { ALIAS, ask, basesDir, call, cliFile, DAY, Failure, gitTry, helperIsThis, inCheckout, readConfig, servedCli, server, setUpCredentialHelper, sharedBy, shown, token, VERSION, writeConfig } from "./core.mjs";
import { folderName, initFolder } from "./bases.mjs";

/** Brings this machine's CLI, its `ubase` link, the installed skills and git's token helper up to date. */
export async function update() {
  if (inCheckout()) {
    console.log(`This CLI runs from the checkout at ${shown(dirname(dirname(cliFile())))}; update it with git pull.`);
  } else {
    const served = await servedCli();
    if (served === readFileSync(cliFile(), "utf8")) console.log(`The CLI is up to date (${VERSION}).`);
    else {
      // Written beside it and renamed over it, so the file is never half written.
      writeFileSync(cliFile() + ".new", served, { mode: 0o755 });
      renameSync(cliFile() + ".new", cliFile());
      console.log(`Updated the CLI at ${shown(cliFile())}.`);
    }
    const alias = aliasState();
    if (alias.state === "missing") {
      symlinkSync(basename(cliFile()), alias.path);
      console.log(`Added ${shown(alias.path)}, so \`${ALIAS}\` works too.`);
    } else if (alias.state === "taken") console.log(`Left ${shown(alias.path)} alone: it isn't this CLI.`);
  }
  const files = await skillFiles();
  const installed = installedSkills();
  if (!installed.length) console.log("No skill is installed here; `usual-base skill` installs it.");
  for (const { dir, link } of installed) {
    if (link) console.log(`Left the skill in ${shown(dir)} alone: it links to ${shown(link)}.`);
    else if (staleFiles(dir, files).length) {
      writeSkill(dir, files);
      console.log(`Updated the skill in ${shown(dir)}.`);
    } else console.log(`The skill in ${shown(dir)} is up to date.`);
  }
  if (token() && !helperIsThis()) {
    setUpCredentialHelper();
    console.log(`git now asks this CLI for the token on ${server}.`);
  }
}

/** Checks this machine's setup, says what to fix, and exits with 1 if anything needs fixing. */
export async function doctor({ flags }) {
  let fixes = 0;
  const report = (status, text) => {
    if (status === "fix") fixes++;
    console.log(`  ${status.padEnd(4)}  ${text}`);
  };
  console.log(`Usual Base CLI ${VERSION}, server ${server}`);
  report("ok", `Node.js ${process.versions.node}`);
  const gitVersion = gitTry(["--version"]);
  const [major, minor] = (gitVersion.stdout.match(/(\d+)\.(\d+)/) || [0, 0, 0]).slice(1).map(Number);
  if (!gitVersion.ok) report("fix", "git isn't installed, and Usual Base needs it.");
  else if (major < 2 || (major === 2 && minor < 28)) report("fix", `${gitVersion.stdout.trim()}: \`usual-base init\` needs git 2.28 or later.`);
  else report("ok", gitVersion.stdout.trim());

  let served = null;
  try {
    served = await servedCli();
  } catch (error) {
    report("fix", `Can't reach ${server}: ${error.message}`);
  }
  const alias = inCheckout() ? null : aliasState();
  if (inCheckout()) report("ok", `The CLI runs from the checkout at ${shown(dirname(dirname(cliFile())))}.`);
  else {
    if (served === readFileSync(cliFile(), "utf8")) report("ok", `The CLI at ${shown(cliFile())} is up to date.`);
    else if (served !== null) report("fix", `The CLI at ${shown(cliFile())} is out of date; run \`usual-base update\`.`);
    if (alias.state === "missing") report("fix", `\`${ALIAS}\` isn't installed; run \`usual-base update\`.`);
    if (alias.state === "taken") report("note", `${shown(alias.path)} is another program, so \`${ALIAS}\` isn't this CLI.`);
  }
  for (const name of ["usual-base", ALIAS]) {
    if (name === ALIAS && alias && alias.state !== "ok") continue; // said above
    const found = onPath(name);
    if (found && realpathSync(found) === cliFile()) report("ok", `\`${name}\` runs this CLI.`);
    else if (found) report("note", `\`${name}\` runs ${shown(found)}, not this CLI.`);
    else if (!inCheckout()) report("fix", `\`${name}\` isn't on your PATH; add ${shown(dirname(cliFile()))} to it.`);
  }

  if (!token()) report("note", "Not connected to a server; `usual-base connect` connects this machine.");
  else {
    try {
      const me = await call("/api/me");
      const t = me.token;
      report("ok", `Connected as "${t.name}" (${t.scope === "write" ? "read and write" : "read only"}, ${t.allBases ? "all Bases" : `${t.baseIds.length} Bases`}).`);
      if (sharedBy().length > 1) report("note", `Agents sharing this connection, each passing its own --as in rooms: ${sharedBy().map((n) => `"${n}"`).join(", ")}.`);
      if (helperIsThis()) report("ok", `git asks this CLI for the token on ${server}.`);
      else report("fix", `git doesn't ask this CLI for the token on ${server}; run \`usual-base update\`.`);
      const { bases } = await call("/api/bases");
      for (const base of bases) {
        const folder = initFolder(base) || join(basesDir(flags), folderName(base.name));
        const top = gitTry(["-C", folder, "rev-parse", "--show-toplevel"]);
        const here = top.ok && top.stdout.trim() === realpathSync(folder) &&
          gitTry(["-C", folder, "config", "--get", "usualbase.base"]).stdout.trim() === base.id;
        if (!here) {
          report("note", `${base.name} isn't on this machine; \`usual-base clone ${base.id}\` clones it.`);
          continue;
        }
        const changes = gitTry(["-C", folder, "status", "--porcelain"]).stdout.split("\n").filter(Boolean).length;
        report("ok", `${base.name}: ${shown(folder)}${changes ? `, ${changes} uncommitted ${changes === 1 ? "change" : "changes"}` : ""}`);
      }
    } catch (error) {
      report("fix", error instanceof Failure ? error.message : `Can't reach ${server}: ${error.message}`);
    }
  }

  try {
    const files = await skillFiles();
    const installed = installedSkills();
    if (!installed.length) report("note", "No skill is installed for agents here; `usual-base skill` installs it.");
    for (const { dir, link } of installed) {
      const current = !staleFiles(dir, files).length;
      if (link) report(current ? "ok" : "note", `The skill in ${shown(dir)} links to ${shown(link)}${current ? " and is up to date." : ", which differs; update that copy."}`);
      else if (current) report("ok", `The skill in ${shown(dir)} is up to date.`);
      else report("fix", `The skill in ${shown(dir)} is out of date; run \`usual-base update\`.`);
    }
  } catch (error) {
    report("fix", `Couldn't get the skill to compare: ${error.message}`);
  }
  console.log(fixes ? `\n${fixes} to fix.` : "\nNothing to fix.");
  if (fixes) process.exitCode = 1;
}

/** The skill's files: the copy beside this CLI in a checkout of the repository, or else the server's. */
export async function skillFiles(signal) {
  const local = join(dirname(cliFile()), "..", "skills", "usual-base");
  if (!inCheckout()) return (await call("/skill.json", { auth: false, signal })).files;
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

// --- Keeping this machine current --------------------------------------------------------------

/** Where a linked folder points. The CLI never writes through a link: it may lead into someone's checkout. */
export function linkedTo(dir) {
  return lstatSync(dir, { throwIfNoEntry: false })?.isSymbolicLink() ? realpathSync(dir) : null;
}

export function writeSkill(dir, files) {
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
}

/** Every copy of the skill in the places `skill` installs to (any Hermes category), and where each links to. */
export function installedSkills() {
  const home = homedir();
  const hermes = join(home, ".hermes", "skills");
  const places = [
    join(home, ".claude", "skills", "usual-base"),
    join(home, ".agents", "skills", "usual-base"),
    ...(existsSync(hermes) ? readdirSync(hermes).map((category) => join(hermes, category, "usual-base")) : []),
    ...hermesProfileSkills(join(home, ".hermes", "profiles")),
    join(home, ".usual-base", "skill"),
  ];
  return places.filter((dir) => existsSync(join(dir, "SKILL.md"))).map((dir) => ({ dir, link: linkedTo(dir) }));
}

/** Each Hermes Bot (profile) keeps its own skills: `profiles/<bot>/skills/<category>/usual-base`. */
function hermesProfileSkills(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir).flatMap((profile) => {
    const skills = join(dir, profile, "skills");
    return existsSync(skills) ? readdirSync(skills).map((category) => join(skills, category, "usual-base")) : [];
  });
}

/** The skill's files that are missing from a copy or differ from it. */
export function staleFiles(dir, files) {
  return Object.keys(files).filter((path) => {
    const file = join(dir, path);
    return !existsSync(file) || readFileSync(file, "utf8") !== files[path];
  });
}

/** `ubase` beside the installed CLI: missing, this CLI, or taken by something else (left alone). */
export function aliasState() {
  const path = join(dirname(cliFile()), ALIAS);
  if (!lstatSync(path, { throwIfNoEntry: false })) return { path, state: "missing" };
  try {
    return { path, state: realpathSync(path) === cliFile() ? "ok" : "taken" };
  } catch {
    return { path, state: "taken" };
  }
}

/** The first executable called `name` on the PATH. */
export function onPath(name) {
  for (const dir of (process.env.PATH || "").split(delimiter).filter(Boolean)) {
    try {
      accessSync(join(dir, name), constants.X_OK);
      return join(dir, name);
    } catch {}
  }
  return null;
}

/** What `update` would change, for the daily check. */
export async function outOfDate(signal) {
  const stale = [];
  if (!inCheckout() && (await servedCli(signal)) !== readFileSync(cliFile(), "utf8")) stale.push("this CLI");
  const files = await skillFiles(signal);
  for (const { dir, link } of installedSkills()) {
    if (!link && staleFiles(dir, files).length) stale.push(`the skill in ${shown(dir)}`);
  }
  return stale;
}

/**
 * Once a day, after a command that works with Bases: if the CLI or an installed skill is out of date, asks
 * whether to update, or with no terminal to ask in, says so on stderr. An unreachable server is tried next time.
 */
export async function offerUpdates() {
  if (Date.now() - (readConfig().lastUpdateCheck || 0) < DAY) return;
  let stale;
  try {
    stale = await outOfDate(AbortSignal.timeout(5000));
  } catch {
    return;
  }
  writeConfig({ ...readConfig(), lastUpdateCheck: Date.now() });
  if (!stale.length) return;
  const what = stale.join(" and ");
  if (!process.stdin.isTTY || !process.stdout.isTTY) return console.error(`Out of date: ${what}. Run \`usual-base update\`.`);
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  rl.on("SIGINT", () => rl.close());
  let answer;
  try {
    answer = await ask(rl, `\nOut of date: ${what}. Update now? [Y/n] `);
  } catch {
    return;
  } finally {
    rl.close();
  }
  if (/^n/i.test(answer.trim())) console.log("Run `usual-base update` when you want to.");
  else await update();
}
