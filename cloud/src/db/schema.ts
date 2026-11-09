// The database schema. After changing it, run `npm run db:generate` to write the next migration.

import { sql } from "drizzle-orm";
import { check, index, integer, primaryKey, sqliteTable, text } from "drizzle-orm/sqlite-core";

// --- Better Auth's tables. The property names are Better Auth's field names; its Drizzle adapter maps them.

export const user = sqliteTable("user", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  email: text("email").notNull().unique(),
  emailVerified: integer("email_verified", { mode: "boolean" }).notNull().default(false),
  image: text("image"),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
});

export const session = sqliteTable("session", {
  id: text("id").primaryKey(),
  expiresAt: integer("expires_at", { mode: "timestamp_ms" }).notNull(),
  token: text("token").notNull().unique(),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
  ipAddress: text("ip_address"),
  userAgent: text("user_agent"),
  userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
}, (t) => [index("session_user").on(t.userId)]);

export const account = sqliteTable("account", {
  id: text("id").primaryKey(),
  accountId: text("account_id").notNull(),
  providerId: text("provider_id").notNull(),
  userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
  accessToken: text("access_token"),
  refreshToken: text("refresh_token"),
  idToken: text("id_token"),
  accessTokenExpiresAt: integer("access_token_expires_at", { mode: "timestamp_ms" }),
  refreshTokenExpiresAt: integer("refresh_token_expires_at", { mode: "timestamp_ms" }),
  scope: text("scope"),
  password: text("password"),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
}, (t) => [index("account_user").on(t.userId)]);

export const verification = sqliteTable("verification", {
  id: text("id").primaryKey(),
  identifier: text("identifier").notNull(),
  value: text("value").notNull(),
  expiresAt: integer("expires_at", { mode: "timestamp_ms" }).notNull(),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
}, (t) => [index("verification_identifier").on(t.identifier)]);

// --- Usual Base's own tables. Times are Unix milliseconds.

/** A Base is one Artifacts repository, named after the Base's id. */
export const bases = sqliteTable("bases", {
  /** The name as a slug plus a random suffix, e.g. "notes-k3x9qa"; also the repository's name. */
  id: text("id").primaryKey(),
  ownerId: text("owner_id").notNull().references(() => user.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  createdAt: integer("created_at").notNull(),
  lastPushAt: integer("last_push_at"),
  /** The pushing token's name. */
  lastPushBy: text("last_push_by"),
}, (t) => [index("bases_owner").on(t.ownerId)]);

/** Tokens for agents (the CLI, sandboxes) and devices (the Mac app). Only a SHA-256 hash is stored. */
export const tokens = sqliteTable("tokens", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  kind: text("kind", { enum: ["agent", "device"] }).notNull(),
  scope: text("scope", { enum: ["read", "write"] }).notNull(),
  /** Every Base the user has, including future ones. Otherwise the Bases in `token_bases`. */
  allBases: integer("all_bases", { mode: "boolean" }).notNull().default(false),
  hash: text("hash").notNull().unique(),
  /** The first characters, to recognize a token in lists. */
  prefix: text("prefix").notNull(),
  createdAt: integer("created_at").notNull(),
  lastUsedAt: integer("last_used_at"),
  revokedAt: integer("revoked_at"),
}, (t) => [
  index("tokens_user").on(t.userId),
  check("tokens_kind", sql`${t.kind} in ('agent', 'device')`),
  check("tokens_scope", sql`${t.scope} in ('read', 'write')`),
]);

export const tokenBases = sqliteTable("token_bases", {
  tokenId: text("token_id").notNull().references(() => tokens.id, { onDelete: "cascade" }),
  baseId: text("base_id").notNull().references(() => bases.id, { onDelete: "cascade" }),
}, (t) => [primaryKey({ columns: [t.tokenId, t.baseId] })]);

/** The device flow (`usual connect`, the Mac app): a client asks, a signed-in person approves. */
export const connectRequests = sqliteTable("connect_requests", {
  /** SHA-256 of the device code the client polls with. */
  deviceHash: text("device_hash").primaryKey(),
  /** What the person sees and types, e.g. "BCDF-GHJK". */
  userCode: text("user_code").notNull().unique(),
  /** What the client calls itself, e.g. "Codex on build-box". */
  clientName: text("client_name").notNull(),
  kind: text("kind", { enum: ["agent", "device"] }).notNull(),
  createdAt: integer("created_at").notNull(),
  expiresAt: integer("expires_at").notNull(),
  status: text("status", { enum: ["pending", "approved", "denied", "used"] }).notNull().default("pending"),
  userId: text("user_id").references(() => user.id, { onDelete: "cascade" }),
  scope: text("scope", { enum: ["read", "write"] }),
  allBases: integer("all_bases", { mode: "boolean" }),
  /** The chosen Bases, when not all of them. */
  baseIds: text("base_ids", { mode: "json" }).$type<string[]>(),
}, (t) => [
  check("connect_requests_kind", sql`${t.kind} in ('agent', 'device')`),
  check("connect_requests_status", sql`${t.status} in ('pending', 'approved', 'denied', 'used')`),
  check("connect_requests_scope", sql`${t.scope} in ('read', 'write')`),
]);

/** Every accepted push, with the token that made it. */
export const pushes = sqliteTable("pushes", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  baseId: text("base_id").notNull().references(() => bases.id, { onDelete: "cascade" }),
  tokenId: text("token_id").references(() => tokens.id, { onDelete: "set null" }),
  tokenName: text("token_name").notNull(),
  ref: text("ref").notNull(),
  oldId: text("old_id").notNull(),
  newId: text("new_id").notNull(),
  at: integer("at").notNull(),
}, (t) => [index("pushes_base").on(t.baseId, t.at)]);
