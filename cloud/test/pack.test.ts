import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { isFastForward, packCommits, readCommands, reportStatus, ZERO_ID } from "../src/pack.ts";

/** A repository with a line of commits, and helpers to pack ranges of it. */
function repo(commitCount: number) {
  const dir = mkdtempSync(join(tmpdir(), "pack-test-"));
  const git = (...args: string[]) =>
    execFileSync("git", ["-C", dir, "-c", "user.name=T", "-c", "user.email=t@x", ...args], { encoding: "utf8" }).trim();
  git("init", "-q", "-b", "main");
  const ids: string[] = [];
  for (let i = 0; i < commitCount; i++) {
    writeFileSync(join(dir, `note-${i}.md`), `note ${i}\n`.repeat(50));
    git("add", ".");
    git("commit", "-qm", `commit ${i}`);
    ids.push(git("rev-parse", "HEAD"));
  }
  const pack = (range: string) =>
    new Uint8Array(execFileSync("git", ["-C", dir, "pack-objects", "--stdout", "--revs"], { input: range + "\n" }));
  return { dir, git, ids, pack, cleanup: () => rmSync(dir, { recursive: true, force: true }) };
}

const noServerHistory = async () => false;

test("reads every commit in a pack with its parents", async () => {
  const r = repo(4);
  try {
    // The notes are alike, so git stores some as deltas; commits are read all the same.
    const { commits } = await packCommits(r.pack(`${r.ids[1]}..${r.ids[3]}`));
    assert.deepEqual([...commits.keys()].sort(), [r.ids[2], r.ids[3]].sort());
    assert.deepEqual(commits.get(r.ids[3]), [r.ids[2]]);
  } finally {
    r.cleanup();
  }
});

test("a push that builds on the old head is a fast-forward", async () => {
  const r = repo(4);
  try {
    const { commits } = await packCommits(r.pack(`${r.ids[1]}..${r.ids[3]}`));
    assert.equal(await isFastForward({ oldId: r.ids[1], newId: r.ids[3], ref: "refs/heads/main" }, commits, noServerHistory), true);
  } finally {
    r.cleanup();
  }
});

test("moving a branch back to an older commit is not a fast-forward", async () => {
  const r = repo(4);
  try {
    // Nothing new to send: the older commit is already on the server, and its history lacks the old head.
    const serverLog = async (start: string, wanted: string) => r.git("rev-list", start).split("\n").includes(wanted);
    const update = { oldId: r.ids[3], newId: r.ids[1], ref: "refs/heads/main" };
    assert.equal(await isFastForward(update, new Map(), serverLog), false);
  } finally {
    r.cleanup();
  }
});

test("a rewritten commit is not a fast-forward", async () => {
  const r = repo(3);
  try {
    r.git("commit", "-q", "--amend", "-m", "rewritten");
    const rewritten = r.git("rev-parse", "HEAD");
    const { commits } = await packCommits(r.pack(`${r.ids[1]}..${rewritten}`));
    const serverLog = async (start: string, wanted: string) => r.git("rev-list", start).split("\n").includes(wanted);
    assert.equal(await isFastForward({ oldId: r.ids[2], newId: rewritten, ref: "refs/heads/main" }, commits, serverLog), false);
  } finally {
    r.cleanup();
  }
});

test("reads ref updates and side-band from a receive-pack request", () => {
  const line = `${ZERO_ID} ${"a".repeat(40)} refs/heads/main\0report-status side-band-64k`;
  const pkt = (line.length + 4).toString(16).padStart(4, "0") + line;
  const bytes = new TextEncoder().encode(pkt + "0000PACK");
  const { commands, packStart, sideband } = readCommands(bytes);
  assert.deepEqual(commands, [{ oldId: ZERO_ID, newId: "a".repeat(40), ref: "refs/heads/main" }]);
  assert.equal(sideband, true);
  assert.equal(new TextDecoder().decode(bytes.subarray(packStart)), "PACK");
});

test("reports a refusal the way git expects", () => {
  const text = new TextDecoder().decode(reportStatus([{ ref: "refs/heads/main", error: "no" }], false));
  assert.equal(text, "000eunpack ok\n001ang refs/heads/main no\n0000");
});
