// The CLI's shared ground: settings, the server and its API, git, and asking in the terminal.

import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";

export const VERSION = "0.2.0";
export const ALIAS = "ubase";
export const DAY = 24 * 60 * 60 * 1000;
export const DEFAULT_SERVER = "https://base.usual.dev";
export const MAX_FILE_BYTES = 32 * 1024 * 1024; // Artifacts refuses larger files
export const MAX_OBJECTS = 45_000; // Artifacts refuses pushes over 50,000 objects

const configPath = join(process.env.XDG_CONFIG_HOME || join(homedir(), ".config"), "usual-base", "config.json");

export function readConfig() {
  try {
    return JSON.parse(readFileSync(configPath, "utf8"));
  } catch {
    return {};
  }
}

export function writeConfig(config) {
  mkdirSync(dirname(configPath), { recursive: true });
  writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n", { mode: 0o600 });
  chmodSync(configPath, 0o600);
}

export const config = readConfig();
export const server = (process.env.USUAL_BASE_SERVER || config.server || DEFAULT_SERVER).replace(/\/$/, "");
export const token = () => process.env.USUAL_BASE_TOKEN || config.token;
export const basesDir = (flags) =>
  resolve(flags.dir || process.env.USUAL_BASE_DIR || config.dir || join(homedir(), "Usual Base"));

export class Failure extends Error {}
export const fail = (message) => {
  throw new Failure(message);
};

/** This CLI's own file, whichever name ran it. */
export const cliFile = () => realpathSync(process.argv[1]);
/** Run from a checkout of the repository, the CLI uses the checkout's skill and is updated with git. */
export const inCheckout = () => existsSync(join(dirname(cliFile()), "..", "skills", "usual-base", "SKILL.md"));
export const shown = (path) => (path.startsWith(homedir() + "/") ? "~" + path.slice(homedir().length) : path);

// --- Arguments ---------------------------------------------------------------------------------

export function parse(argv) {
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

export async function call(path, { method = "GET", body, auth = true, signal = AbortSignal.timeout(30_000) } = {}) {
  const headers = { "content-type": "application/json", "user-agent": `usual-cli/${VERSION}` };
  if (auth) {
    if (!token()) fail("Not connected. Run `usual-base connect` first, or set USUAL_BASE_TOKEN.");
    headers.authorization = `Bearer ${token()}`;
  }
  const response = await fetch(server + path, { method, headers, body: body && JSON.stringify(body), signal });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) fail(data.error || `${method} ${path} failed with HTTP ${response.status}`);
  return data;
}

/** The CLI as the server hands it out, to compare with this one. */
export async function servedCli(signal = AbortSignal.timeout(30_000)) {
  const response = await fetch(server + "/cli/usual-base.mjs", { signal, headers: { "user-agent": `usual-cli/${VERSION}` } });
  if (!response.ok) fail(`${server}/cli/usual-base.mjs answered HTTP ${response.status}.`);
  return response.text();
}

// --- Git ---------------------------------------------------------------------------------------

export function git(args, options = {}) {
  return execFileSync("git", args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], ...options }).trim();
}

export function gitTry(args, options = {}) {
  const result = spawnSync("git", args, { encoding: "utf8", ...options });
  return { ok: result.status === 0, stdout: result.stdout || "", out: (result.stdout || "") + (result.stderr || "") };
}

export const helperKey = () => `credential.${server}.helper`;
export const helperCommand = () => `!'${process.execPath}' '${cliFile()}' credential`;
export const helperIsThis = () => gitTry(["config", "--global", "--get-all", helperKey()]).stdout.split("\n").includes(helperCommand());

/** Makes git ask this CLI for the token whenever it talks to the server, and nothing else. */
export function setUpCredentialHelper() {
  gitTry(["config", "--global", "--unset-all", helperKey()]);
  // The empty value first clears helpers set for every host (such as the macOS keychain).
  git(["config", "--global", "--add", helperKey(), ""]);
  git(["config", "--global", "--add", helperKey(), helperCommand()]);
}

/** One answer from the terminal; Ctrl-C or Ctrl-D stops without changing anything. */
export function ask(rl, prompt) {
  return new Promise((done, stop) => {
    const closed = () => stop(new Failure("\nStopped; nothing changed."));
    rl.once("close", closed);
    rl.question(prompt, (answer) => {
      rl.off("close", closed);
      done(answer);
    });
  });
}
