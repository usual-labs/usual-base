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
  usual-base init [FOLDER] [--base BASE | --name NAME]
                                                 make a folder a Base where it is; asks which Base without either
  usual-base bases                               list the Bases this token can read
  usual-base clone <base>… | --all [--dir DIR]   clone Bases (default folder: ~/Usual Base)
  usual-base import <folder> --name NAME [--history]
                                                 create a Base from an existing knowledge base
  usual-base path <base>                         print where a Base is cloned
  usual-base whoami | logout

--history keeps the folder's git history, even for a subfolder of a bigger repository.
Once a day, the commands that work with Bases check whether this CLI or a skill is out of date.
USUAL_BASE_TOKEN, USUAL_BASE_SERVER and USUAL_BASE_DIR override the saved settings.`;

// The commands after which the daily update check runs; never `credential`, whose output git reads.
const CHECKED = new Set(["sync", "import", "connect", "init", "bases", "clone", "path", "whoami"]);

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
