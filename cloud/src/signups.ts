/** Whether `email` may create an account under the SIGNUPS setting. */
export function signupsAllow(setting: string | undefined, email: string): boolean {
  const value = (setting ?? "").trim().toLowerCase();
  if (value === "open") return true;
  return value.split(",").map((entry) => entry.trim()).filter(Boolean).includes(email.trim().toLowerCase());
}

