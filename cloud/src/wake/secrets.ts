// Wake secrets (a Grok Bot routine's key, say) are stored encrypted: AES-GCM with a key derived from
// BETTER_AUTH_SECRET by HKDF, so running a server needs no extra setting. Changing BETTER_AUTH_SECRET makes stored
// secrets unreadable; their wakes then fail until the person enters them again.

import type { Env } from "../env";

const text = new TextEncoder();
const toBase64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
const fromBase64 = (value: string) => Uint8Array.from(atob(value), (c) => c.charCodeAt(0));

async function key(env: Env) {
  const material = await crypto.subtle.importKey("raw", text.encode(env.BETTER_AUTH_SECRET), "HKDF", false, ["deriveKey"]);
  return crypto.subtle.deriveKey(
    { name: "HKDF", hash: "SHA-256", salt: text.encode("usual-base"), info: text.encode("wake secrets") },
    material, { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
}

export async function seal(env: Env, plain: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await key(env), text.encode(plain)));
  return `v1:${toBase64(iv)}:${toBase64(sealed)}`;
}

export async function unseal(env: Env, sealed: string): Promise<string> {
  const [version, iv, data] = sealed.split(":");
  if (version !== "v1" || !iv || !data) throw new Error("unknown secret format");
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: fromBase64(iv) }, await key(env), fromBase64(data));
  return new TextDecoder().decode(plain);
}
