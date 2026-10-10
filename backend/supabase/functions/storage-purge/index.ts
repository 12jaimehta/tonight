import { createStorageClient, handleStoragePurge, purgeDue, purgeOlderThan } from "./handler.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

Deno.serve((req) => {
  const storage = createStorageClient({
    supabaseUrl,
    serviceKey,
    bucket: "study-audio",
    fetchImpl: globalThis.fetch,
  });
  return handleStoragePurge(req, {
    purgeDue: () =>
      purgeDue({
        due: () => dueRows(supabaseUrl, serviceKey),
        storage,
        markDone: (id) => markDone(supabaseUrl, serviceKey, id),
      }),
    purgeRetention: () => purgeOlderThan({ storage, days: 90, now: new Date() }),
  });
});

async function dueRows(supabaseUrl: string, serviceKey: string) {
  const now = new Date().toISOString();
  const response = await fetch(
    `${supabaseUrl}/rest/v1/storage_deletion_queue?deleted_at=is.null&delete_after=lte.${encodeURIComponent(now)}&select=id,bucket_id,object_prefix`,
    {
      headers: {
        apikey: serviceKey,
        authorization: `Bearer ${serviceKey}`,
      },
    },
  );
  if (!response.ok) throw new Error("deletion_queue_read_failed");
  const rows = await response.json();
  if (!Array.isArray(rows)) return [];
  return rows.flatMap((row) => {
    if (!row || typeof row !== "object") return [];
    const record = row as { id?: unknown; bucket_id?: unknown; object_prefix?: unknown };
    if (typeof record.id !== "string" || typeof record.bucket_id !== "string" || typeof record.object_prefix !== "string") {
      return [];
    }
    return [{ id: record.id, bucketId: record.bucket_id, objectPrefix: record.object_prefix }];
  });
}

async function markDone(supabaseUrl: string, serviceKey: string, id: string) {
  const response = await fetch(
    `${supabaseUrl}/rest/v1/storage_deletion_queue?id=eq.${encodeURIComponent(id)}`,
    {
      method: "PATCH",
      headers: {
        apikey: serviceKey,
        authorization: `Bearer ${serviceKey}`,
        "content-type": "application/json",
        prefer: "return=minimal",
      },
      body: JSON.stringify({ deleted_at: new Date().toISOString() }),
    },
  );
  if (!response.ok) throw new Error("deletion_queue_mark_failed");
  await response.body?.cancel();
}
