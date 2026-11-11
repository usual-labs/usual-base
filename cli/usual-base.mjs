#!/usr/bin/env node
// Usual Base CLI: syncs a Base with any git repository, imports an existing knowledge base, installs the agent
// skill, and connects to a Usual Base server (base.usual.dev, or one implementing docs/protocol.md).
// No dependencies; needs Node.js 18+ and git. Installed as `usual-base`, with `ubase` as a link to it. The source
// is split into cli/lib/; the server hands it out bundled into one file (cloud/scripts/embed.mjs).

import { ALIAS, Failure, parse, server, VERSION } from "./lib/core.mjs";
import { offerUpdates } from "./lib/upkeep.mjs";
import { commands } from "./lib/commands.mjs";

// --- Main --------------------------------------------------------------------------------------

const help = `Usual Base CLI ${VERSION}, also installed as ${ALIAS}

With any git repository (GitHub, GitLab, Forgejo, a bare repository…):
  usual-base sync [PATH]                         pull, then push your commits
  usual-base import <folder> --to GIT_URL [--history]
                                                 push an existing knowledge base into an empty repository

This machine:
  usual-base skill [--to DIR]                    install the usual-base agent skill
  usual-base update                              update this CLI and the installed skills
  usual-base doctor                              check the setup and say what to fix

With a Usual Base server (${server}):
  usual-base connect [--name NAME] [--dir DIR]   connect this machine; you approve it in the browser
  usual-base init                                in a terminal: a Base for the project you're in; asks which
                                                 Base, where its folder goes (it may be inside the project) and
                                                 whether the project's Claude Code uses it, then does it
  usual-base init FOLDER [--base BASE | --name NAME]
                                                 make a folder a Base where it is, even inside a project
  usual-base bases                               list the Bases this token can read
  usual-base clone <base>… | --all [--dir DIR]   clone Bases (default folder: ~/Usual Base)
  usual-base import <folder> --name NAME [--history]
                                                 create a Base from an existing knowledge base
  usual-base path <base>                         print where a Base is cloned
  usual-base whoami | logout

Rooms, where people and agents talk in a Base (one file per message; works with any git remote):
  usual-base room list                           the Base's rooms, and what's new in each
  usual-base room create <name> [--about TEXT]   start a room
  usual-base room read <room> [--all | --last N] [--json]
                                                 show what's new since you last read, and mark it read
  usual-base room say <room> <message> [--re FILE] [--anyway]
                                                 post; shows you any messages you hadn't read instead
  usual-base room wait <room> [--timeout SECONDS]
                                                 block until someone posts (default 600 s; exits 2 if not)
  usual-base room join <room> | leave <room>     become a member (members are woken), or stop
  usual-base room news [--intro]                 what's new in your rooms; prints nothing if nothing is
  They take --base FOLDER|NAME for the Base, and --as NAME (or USUAL_BASE_NAME) for who you are.

Agents:
  usual-base setup claude-code <folder> [--name NAME] [--base BASE] [--wake] [--remove]
                                                 make that project's Claude Code an agent of the Base
  usual-base setup hermes <profile>… | --all [--base BASE] [--wake] [--remove]
                                                 make Hermes Bots agents of the Base (run where Hermes runs)
  usual-base relay [install | uninstall | status]
                                                 wake agents set up with --wake when their rooms get messages
  A Grok Bot is woken by the server instead: see Connect an agent on ${server}.

--history keeps the folder's git history, even for a subfolder of a bigger repository.
Once a day, the commands that work with Bases check whether this CLI or a skill is out of date.
USUAL_BASE_TOKEN, USUAL_BASE_SERVER and USUAL_BASE_DIR override the saved settings.`;

// The commands after which the daily update check runs; never `credential`, whose output git reads.
const CHECKED = new Set(["sync", "import", "connect", "init", "bases", "clone", "path", "whoami", "room"]);

const [command, ...rest] = process.argv.slice(2);
if (!command || command === "help" || command === "--help" || command === "-h") console.log(help);
else if (command === "--version" || command === "version") console.log(VERSION);
else if (!Object.hasOwn(commands, command)) {
  console.error(`Unknown command: ${command}\n\n${help}`);
  process.exit(2);
} else {
  commands[command](parse(rest))
    .then(() => CHECKED.has(command) && offerUpdates())
    .catch((error) => {
      console.error(error instanceof Failure ? error.message : error.stack || String(error));
      process.exit(1);
    });
}
