// Deletes object bytes through the Storage API. A queue row is finished only
// after a follow-up list for that prefix is empty. The removed study-audio
// bucket and rows with no bucket are marked done without a list call.

export type StorageObject = { name: string; createdAt?: string };

export type StorageClient = {
  list(prefix: string): Promise<StorageObject[]>;
  remove(names: string[]): Promise<void>;
};

export type DeletionQueueRow = {
  id: string;
  bucketId: string;
  objectPrefix: string;
};

export type PurgeDeps = {
  due: () => Promise<DeletionQueueRow[]>;
  storage: StorageClient;
  markDone: (id: string) => Promise<void>;
  /** Buckets that are not in Storage. Those rows are marked done and do not call list. */
  absentBuckets?: string[];
};

export type PurgeResult = {
  deletedIds: string[];
  remaining: string[];
};

export async function handleStoragePurge(
  req: Request,
  deps: {
    purgeDue: () => Promise<PurgeResult>;
    purgeRetention?: () => Promise<{ removed: string[] }>;
  },
): Promise<Response> {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  const role = bearerRole(req.headers.get("authorization") ?? "");
  if (role === null) {
    return json({ error: "missing_token" }, 401);
  }
  if (role !== "service_role") {
    return json({ error: "forbidden" }, 403);
  }
  let mode = "due";
  const text = await req.text();
  if (text.trim().length > 0) {
    try {
      const parsed = JSON.parse(text) as { mode?: unknown };
      if (parsed && parsed.mode === "retention") mode = "retention";
    } catch {
      return json({ error: "invalid_json" }, 400);
    }
  }
  if (mode === "retention") {
    if (!deps.purgeRetention) return json({ error: "retention_unavailable" }, 500);
    return json(await deps.purgeRetention(), 200);
  }
  return json(await deps.purgeDue(), 200);
}

const DAY_MS = 24 * 60 * 60 * 1000;

/** Deletes object bytes older than `days`. Rows are not the thing being removed. */
export async function purgeOlderThan(deps: {
  storage: StorageClient;
  days: number;
  now: Date;
}): Promise<{ removed: string[] }> {
  const cutoff = deps.now.getTime() - deps.days * DAY_MS;
  const stale = (await deps.storage.list("")).filter((object) => {
    if (!object.createdAt) return false;
    const created = Date.parse(object.createdAt);
    return Number.isFinite(created) && created < cutoff;
  });
  if (stale.length > 0) {
    await deps.storage.remove(stale.map((object) => object.name));
  }
  return { removed: stale.map((object) => object.name) };
}

export async function purgeDue(deps: PurgeDeps): Promise<PurgeResult> {
  const deletedIds: string[] = [];
  const remaining: string[] = [];
  const absent = new Set(deps.absentBuckets ?? ["none", "study-audio"]);
  for (const row of await deps.due()) {
    try {
      if (absent.has(row.bucketId)) {
        await deps.markDone(row.id);
        deletedIds.push(row.id);
        continue;
      }
      const names = (await deps.storage.list(row.objectPrefix)).map((object) => object.name);
      if (names.length > 0) {
        await deps.storage.remove(names);
      }
      const after = await deps.storage.list(row.objectPrefix);
      if (after.length > 0) {
        remaining.push(...after.map((object) => object.name));
        continue;
      }
      await deps.markDone(row.id);
      deletedIds.push(row.id);
    } catch {
      remaining.push(row.objectPrefix);
    }
  }
  return { deletedIds, remaining };
}

function bearerRole(header: string): string | null {
  const match = /^Bearer\s+(\S+)/.exec(header.trim());
  if (!match) return null;
  const payload = match[1].split(".")[1];
  if (!payload) return null;
  try {
    const parsed = JSON.parse(decodeBase64Url(payload)) as { role?: unknown };
    return typeof parsed.role === "string" ? parsed.role : null;
  } catch {
    return null;
  }
}

function decodeBase64Url(segment: string): string {
  const padded = segment.replaceAll("-", "+").replaceAll("_", "/") +
    "=".repeat((4 - (segment.length % 4)) % 4);
  return atob(padded);
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

type FetchLike = (input: string, init: RequestInit) => Promise<Response>;

export function createStorageClient(deps: {
  supabaseUrl: string;
  serviceKey: string;
  bucket: string;
  fetchImpl: FetchLike;
  pageSize?: number;
}): StorageClient {
  const headers = {
    authorization: `Bearer ${deps.serviceKey}`,
    apikey: deps.serviceKey,
    "content-type": "application/json",
  };
  const pageSize = deps.pageSize ?? 1000;
  async function page(prefix: string, offset: number): Promise<Record<string, unknown>[]> {
    const response = await deps.fetchImpl(
      `${deps.supabaseUrl}/storage/v1/object/list/${deps.bucket}`,
      { method: "POST", headers, body: JSON.stringify({ prefix, limit: pageSize, offset }) },
    );
    if (!response.ok) throw new Error("storage_list_failed");
    const rows = await response.json();
    if (!Array.isArray(rows)) return [];
    return rows.filter((row) => row && typeof row === "object") as Record<string, unknown>[];
  }
  async function walk(prefix: string, into: StorageObject[]): Promise<void> {
    let offset = 0;
    for (;;) {
      const rows = await page(prefix, offset);
      for (const row of rows) {
        if (typeof row.name !== "string" || row.name.length === 0) continue;
        if (row.id === null) {
          const folder = row.name.replace(/\/$/, "");
          await walk(`${prefix}${folder}/`, into);
          continue;
        }
        const object: StorageObject = { name: `${prefix}${row.name}` };
        if (typeof row.created_at === "string") object.createdAt = row.created_at;
        into.push(object);
      }
      if (rows.length < pageSize) return;
      offset += rows.length;
    }
  }
  return {
    async list(prefix) {
      const found: StorageObject[] = [];
      await walk(prefix, found);
      return found;
    },
    async remove(names) {
      if (names.length === 0) return;
      const response = await deps.fetchImpl(
        `${deps.supabaseUrl}/storage/v1/object/${deps.bucket}`,
        { method: "DELETE", headers, body: JSON.stringify(names) },
      );
      if (!response.ok) throw new Error("storage_remove_failed");
      await response.body?.cancel();
    },
  };
}
