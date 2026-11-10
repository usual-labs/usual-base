---
name: usual-base
description: Read, search and write the user's Usual Base, a shared Markdown knowledge base and memory. People read it in the Usual Base Mac app; agents read and write it as plain files, often synced through git. Use when the user mentions their Base or Usual Base, asks you to remember something or to look up what's already known, when you should save findings, decisions or notes for later sessions and other agents, or when the user asks you to set up Usual Base.
---

# Usual Base

A Base is a folder of Markdown files that a person and their agents share. You work with it as plain files:
no API, no special client. The person reads and edits the same files in the Usual Base Mac app, which shows
them rendered, picks up your changes within a moment, and can sync the folder with a git repository so agents
on other machines and in the cloud share it too.

What Usual Base gives you today. Anything not listed here doesn't exist yet.

| Feature | What it means for you | Details |
|---|---|---|
| Plain files | Read, search and edit with your usual file tools. | Below |
| Properties | Front matter at the top of a note becomes a card in the app. | [references/markdown.md](references/markdown.md) |
| Rendered view | People mostly read your notes rendered: tables, tasks, code, links, pictures. | [references/markdown.md](references/markdown.md) |
| Sync and history | Optional git sync. History records who changed what. | [references/sync.md](references/sync.md) |
| Hosted Bases | Bases on base.usual.dev, reached with the `usual-base` CLI and your own token. | [references/sync.md](references/sync.md#hosted-bases) |
| Conflict copies | A clash never loses text; it leaves a copy to merge. | Below |

## Find the Base

- **Where it is:** your instructions or memory say where the Base is, either a folder on this machine or a
  clone of its git repository. If they don't, ask the user. Don't search the disk for it.
- **Its own rules:** if the Base has an `AGENTS.md` at its root, read it first. It describes how this Base is
  organized, and it overrides the defaults in this skill.
- **How it's kept in sync:** see [Git](#git) below.

## Read and search

- The app shows `.md` and `.markdown` files. It hides dot-folders, `node_modules`, `.build` and `DerivedData`.
  Hidden files still sync with everything else unless `.gitignore` excludes them.
- Search before you write (`rg`, `grep`, or your search tool). If a note on the topic exists, update it rather
  than adding a near-duplicate.
- Notes link to each other with relative links. Follow them for context.

## Write

- **Edit in place, narrowly.** Change only the lines that need changing. The app never reformats a file, so
  whatever you write is exactly what's on disk and in history.
- **Read the file right before you edit it.** People and other agents edit the same files.
- **Keep what's there:** the front matter, line endings and the file's own style.
- **One topic per note**, with a file name that reads as a title; it is the title in the app's sidebar. Follow
  the folders the Base already has.
- **Start a new note with properties:** at least `title` and `description`. See
  [references/markdown.md](references/markdown.md).
- **Link related notes** with relative links, `[Deploys](../Ops/Deploys.md)`, or from the Base's root,
  `[Deploys](/Ops/Deploys.md)`.
  - In a path with spaces, write each space as `%20`: `[Deploying](Ops/Deploying%20the%20API.md)`.
  - Use standard Markdown links. `[[wiki links]]` show as plain text.
- **Keep it current.** Rewrite a fact that changed instead of adding a contradicting one below it. Put a date
  on facts that will age ("as of 2026-11-07").
- **No secrets.** Never write tokens, passwords, keys or private personal data. The Base syncs to a remote, and
  every agent can read it.
- **Ask before** deleting, renaming or moving notes you didn't create, and before reorganizing a folder.
  Conflict copies are the exception (below).

## Conflict copies

A clash never loses text. The losing version goes next to the file as `Name (conflict 2026-11-07 14.30).md`:

- **You write a file while a person has unsaved edits in it:** your version stays at the path, and the
  person's edits go to the copy.
- **A sync finds the same lines changed on this Mac and on the remote:** the remote's version stays at the
  path, and this Mac's version goes to the copy. That can be your own recent edit.

When you find a file with `(conflict ` in its name:

1. See what changed. Compare the copy with the original. In a git Base, `git log -p -- "<original>"` shows the
   recent changes on each side.
2. Merge into the original whatever the copy has that the original lacks, keeping both sides' facts.
3. Delete the copy. You may do this without asking, once its content is in the original.

If the two versions contradict each other and you can't tell which is right, ask the user.

## Git

Find out which case you're in:

```sh
git -C "$BASE" rev-parse --show-toplevel    # the Base's own path, if it's a git repository
git -C "$BASE" config --get usualbase.sync  # "true" if the Mac app syncs it
```

- **The app syncs it** (`usualbase.sync` is `true`). This is the person's Base on their Mac. Write the files;
  the app commits and pushes about 5 seconds after the folder goes quiet, and pulls every minute. To be
  credited by name, commit your own change right after writing it, under your own name. Don't push; the app
  does.
- **A git repository the app doesn't sync**, such as a clone on another machine, in a cloud sandbox, or one you
  made yourself. Pull with rebase before you start, commit under your own name, and push. If the push is
  refused, pull with rebase and push again. Never force-push.
- **Not a git repository:** just files. Nothing to do.
- **Inside a bigger repository:** `--show-toplevel` prints a folder above the Base. That repository isn't the
  Base's. Don't commit or push it unless the user asks.

Commands, credentials and history are in [references/sync.md](references/sync.md).

## Set up

Follow this when the user asks you to set up Usual Base for yourself (the setup prompt in the Usual Base README
sends you here). Ask the user for anything you're missing. Don't write anything into the Base during setup
unless the user says so.

1. **Find the Base.** The user gives you a folder on this machine, the Base's git URL, or their hosted Usual Base.
   - **Hosted Usual Base** (base.usual.dev): install the CLI (`curl -fsSL https://base.usual.dev/install.sh | sh`)
     and run `usual-base connect --name "<your platform> on <this machine>"`. Show the user the link and code it
     prints and wait while they approve. It clones every Base you may use into `~/Usual Base/`, installs this skill
     and prints the lines for step 3, so skip step 2.
   - For a URL, clone it to a stable place, such as `~/Bases/<name>`, or wherever the user prefers.
   - If the clone needs credentials, ask the user for a token. Ideally each agent gets its own token, with
     write access only if it should write. Handle it as described under "Credentials" in
     [references/sync.md](references/sync.md).
2. **Install this skill** where your agent loads skills, as a folder named `usual-base` holding `SKILL.md` and
   `references/`:
   - Claude Code: `~/.claude/skills/usual-base/`
   - Codex and Cursor: `~/.agents/skills/usual-base/`
   - Hermes: `~/.hermes/skills/<category>/usual-base/`; any category name works, such as `knowledge`.

   Where the skill comes from:
   - **The user gave a folder:** copy it. If that folder is a checkout the user keeps, you can link to it instead
     so the skill stays current; ask which they prefer.
   - **The user gave a repository URL:** clone the repository to a temporary folder and copy its
     `skills/usual-base` folder.
   - **A `usual-base` skill is already installed:** replace it. That's an update.

   If your agent doesn't load skills, copy the folder to a lasting place outside the Base instead, such as
   `~/.usual-base/skill/`. Step 3 then points at it.
3. **Remember the Base.** Add these lines to your global instructions or memory file (for example
   `~/.claude/CLAUDE.md` or `~/.codex/AGENTS.md`):

   ```markdown
   - Usual Base: <the Base's absolute path>. <One of: "Synced by the Usual Base app on this Mac." / "A git clone of <URL without credentials>." / "A plain folder, no git.">
   - Use the usual-base skill to look things up there before asking, and to save what should outlast this session.
   ```

   - Without skills, write the second line as "Before using it, read `<absolute path to the copied SKILL.md>`."
   - If you have no global instructions file, tell the user and ask where to keep these lines.
   - Show the user what you added.
4. **Check.**
   - List the Base, and read its `AGENTS.md` or any note.
   - For a git Base, run `git status` and `git remote -v`, and make sure no token appears in the output.
5. **Report and offer.** Tell the user what you set up. If the Base has no `AGENTS.md`, offer to draft one that
   describes its folders and rules; write it only if they agree.
