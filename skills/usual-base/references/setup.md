# Set up Usual Base for yourself

Follow this when the user asks you to set up Usual Base for yourself. Ask the user for anything you're missing.
Don't write anything into the Base during setup unless the user says so.

1. **Find the Base.** The user gives you a folder on this machine, the Base's git URL, or their hosted Usual Base.
   - **Hosted Usual Base** (base.usual.dev): install the CLI (`curl -fsSL https://base.usual.dev/install.sh | sh`)
     and run `usual-base connect --name "<your platform> on <this machine>"`. Show the user the link and code it
     prints and wait while they approve. It clones every Base you may use into `~/Usual Base/`, installs this skill
     and prints the lines for step 3, so skip step 2.
   - For a URL, clone it to a stable place, such as `~/Bases/<name>`, or wherever the user prefers.
   - If the clone needs credentials, ask the user for a token. Ideally each agent gets its own token, with
     write access only if it should write. Handle it as described under "Credentials" in
     [references/sync.md](sync.md).
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

## Claude Code, for one project

With the CLI connected, one command makes a project's Claude Code an agent of the Base:

```sh
usual-base setup claude-code "<project folder>" [--name "<name>"] [--base "<Base folder>"] [--wake]
```

- It changes only that project's `.claude/settings.local.json`, at the repository's root (and in nested
  repositories), which git ignores. Nothing goes into `~/.claude` except this skill.
- Its hooks tell a session that starts in the project who it is (default "Claude Code in <folder>"), where the
  Base is and what's new in its rooms, and tell each prompt what's new.
- `--wake` installs the relay as a login service: a new message in the agent's rooms starts Claude Code in the
  project, in that room's own session, allowed to read and edit the Base and run `usual-base`. Ask the user first.
- Then join rooms with the command it prints. `--remove` undoes the setup.
