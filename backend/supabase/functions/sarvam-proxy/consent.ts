import type { FetchLike } from "./jwt.ts";

// Active server_speech means a row for this parent and child, version present,
// withdrawn_at null, and scopes containing server_speech. Anything else is denied.

export function createConsentLookup(deps: {
  supabaseUrl: string;
  anonKey: string;
  fetchImpl: FetchLike;
}): (input: { parentId: string; childProfileId: string; accessToken: string }) => Promise<boolean> {
  return async ({ parentId, childProfileId, accessToken }) => {
    if (!deps.supabaseUrl) throw new Error("consent_lookup_unconfigured");
    const url = new URL("/rest/v1/consent_record", deps.supabaseUrl);
    url.searchParams.set("select", "version,scopes,withdrawn_at");
    url.searchParams.set("parent_id", `eq.${parentId}`);
    url.searchParams.set("child_profile_id", `eq.${childProfileId}`);
    url.searchParams.set("withdrawn_at", "is.null");
    url.searchParams.set("scopes", "cs.{server_speech}");

    const response = await deps.fetchImpl(url.toString(), {
      method: "GET",
      headers: {
        authorization: `Bearer ${accessToken}`,
        apikey: deps.anonKey,
        accept: "application/json",
      },
    });
    if (!response.ok) {
      await response.body?.cancel();
      throw new Error("consent_lookup_failed");
    }
    const rows = await response.json();
    if (!Array.isArray(rows)) return false;
    return rows.some((row) => {
      if (!row || typeof row !== "object") return false;
      const record = row as { version?: unknown; scopes?: unknown; withdrawn_at?: unknown };
      return typeof record.version === "string" &&
        record.version.trim().length > 0 &&
        record.withdrawn_at == null &&
        Array.isArray(record.scopes) &&
        record.scopes.includes("server_speech");
    });
  };
}
