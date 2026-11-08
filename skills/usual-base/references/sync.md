# Git sync, history and conflicts

A Base can be an ordinary git repository. The Mac app syncs it only if someone turned sync on for it, which sets
`usualbase.sync = true` in the repository's own config:

```sh
git -C "$BASE" config --get usualbase.sync   # prints "true" when the app syncs this folder
```

What the app does while it's open:

- Commits every change in the folder about 5 seconds after the folder goes quiet. It skips files matched by
  `.gitignore`, and `.DS_Store`.
- Pushes, and fetches every 60 seconds and when the app comes to the front.
- Replays this Mac's commits on top of the remote's instead of merging, so history stays a straight line and each
  commit keeps its author. (Only if this Mac's history already has a merge commit does it merge.)
- When the same lines changed on both sides, keeps the remote's version at the path and commits this Mac's as
  `Name (conflict yyyy-MM-dd HH.mm).md`.
- Never overwrites a file that changed while it was syncing. It stops, and tries again once the folder is quiet.

## On the Mac where the app syncs

Write the files; the app commits and pushes them. Its commits carry the Mac's author name. To be credited
instead, commit your own change right after writing it:

```sh
git -C "$BASE" add -- "Ops/Deploying the API.md"
git -C "$BASE" -c user.name="Claude Code" -c user.email="claude-code@agents.invalid" \
    commit -m "Deploying the API: add the rollback check"
```

- Name yourself after your platform, the same way every time, with a stable email. Setting both with `-c` makes
  you the author and the committer, and works on a machine with no git identity. Never use the person's name.
- Commit only the paths you changed. "Nothing to commit" means the app committed your change first; that's fine.
- Don't push; the app pushes within seconds.
- If git says `index.lock` exists, the app is in the middle of a sync. Wait a second and try again. Never delete
  the lock file.
- Don't switch branches, rebase, reset or otherwise rewrite history in this folder. The app syncs the branch
  that's checked out.

## In a repository the app doesn't sync (another machine, a cloud sandbox, your own clone)

```sh
git pull --rebase                 # before you start, and before you push
# … edit …
git add -- <the files you changed>
git -c user.name="Codex" -c user.email="codex@agents.invalid" commit -m "Deploying the API: add the rollback check"
git push                          # refused? git pull --rebase, then git push again
```

- Pull at the start of a session and push before it ends, so others see your work.
- Rebase, don't merge; the Base's history is a straight line.
- Never force-push. It would delete other people's and agents' work.
- **If a rebase stops on a conflict:**
  - Combine both sides by hand, keeping both people's facts, then `git add` the file and run
    `git rebase --continue`.
  - If the two versions truly contradict, keep the remote's text at the path and save yours as
    `Name (conflict yyyy-MM-dd HH.mm).md`, the same convention the app uses. Then tell the user.

## Credentials

- Remotes use HTTPS with a token as the password. SSH isn't supported by the Mac app yet.
- Keep the token in your platform's secret store or git's credential helper (`osxkeychain` on a Mac). Never in
  the remote URL, `.git/config`, a note, or your instructions.
- Don't repeat a token in chat, and don't put it on a command line, where it lands in shell history. If you can't
  store it without exposing it, ask the user to run the first clone or fetch in their own terminal; the credential
  helper then remembers it.
- Some cloud platforms remove secrets before the agent runs. If you can't push, ask the user how pushes should
  work there; don't work around it.

## History

Every change is a commit, so history answers "who changed this, and when":

```sh
git -C "$BASE" log --format='%h %ad %an  %s' --date=short -- "Ops/Deploying the API.md"
git -C "$BASE" show <commit> -- "Ops/Deploying the API.md"
```

The app's own commits are named after what changed, such as "Update Deploying the API.md" or "Add 3 files".
