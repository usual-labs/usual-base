import assert from "node:assert/strict";
import { test } from "node:test";
import { signupsAllow } from "../src/signups.ts";

test("sign-ups: closed unless open or the email is listed", () => {
  assert.equal(signupsAllow(undefined, "a@b.c"), false);
  assert.equal(signupsAllow("", "a@b.c"), false);
  assert.equal(signupsAllow("open", "a@b.c"), true);
  assert.equal(signupsAllow(" A@b.c , x@y.z", "a@B.c"), true);
  assert.equal(signupsAllow("x@y.z", "a@b.c"), false);
});
