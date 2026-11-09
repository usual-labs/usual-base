import { defineConfig } from "drizzle-kit";

// `npm run db:generate` writes migrations here; Wrangler applies them (`npm run dev` / `npm run deploy`).
export default defineConfig({
  dialect: "sqlite",
  schema: "./src/db/schema.ts",
  out: "./migrations",
});
