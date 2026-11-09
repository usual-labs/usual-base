import type { BaseSQLiteDatabase } from "drizzle-orm/sqlite-core";
import type { LibSQLDatabase } from "drizzle-orm/libsql";
import * as schema from "./schema";

export * from "./schema";
export { schema };

/** Drizzle over SQLite: D1 on Cloudflare, a libSQL file on Node. Both drivers also send batches. */
export type Database = BaseSQLiteDatabase<"async", unknown, typeof schema> & {
  batch: LibSQLDatabase<typeof schema>["batch"];
};
